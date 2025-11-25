import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';  // Add explicit import for Timer and TimeoutException
import 'package:http/http.dart' as http;
import '../services/drug_api_service.dart' hide Medicine;
import '../models/medicine.dart';
import 'card_detail_screen.dart';
import 'medicine_search_screen.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class PrescriptionScannerScreen extends StatefulWidget {
  final Function(Map<String, dynamic>)? onPrescriptionScanned;

  PrescriptionScannerScreen({this.onPrescriptionScanned});

  static Map<String, Map<String, dynamic>> _prescriptionCache = {};
  static const int _MAX_CACHE_SIZE = 50; // Increased cache size
  static const int _MAX_CACHE_AGE_MS = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds
  static const String _DEFAULT_GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro:generateContent';
  
  // Improved cache management system
  static void _limitCacheSize() {
    if (_prescriptionCache.length > _MAX_CACHE_SIZE) {
      // Sort cache entries by timestamp (oldest first) and remove oldest entries
      final sortedEntries = _prescriptionCache.entries.toList()
        ..sort((a, b) {
          final aTimestamp = a.value['_timestamp'] as int? ?? 0;
          final bTimestamp = b.value['_timestamp'] as int? ?? 0;
          return aTimestamp.compareTo(bTimestamp);
        });
      
      // Keep only the most recent entries
      final keysToRemove = sortedEntries
          .take(sortedEntries.length - _MAX_CACHE_SIZE)
          .map((entry) => entry.key)
          .toList();
      
      for (final key in keysToRemove) {
        _prescriptionCache.remove(key);
      }
    }
  }
  
  // Improved expired entries removal with validation status tracking
  static void _removeExpiredEntries() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    final keysToRemove = <String>[];
    int expiredCount = 0;
    
    _prescriptionCache.forEach((key, value) {
      final timestamp = value['_timestamp'] as int?;
      if (timestamp != null) {
        if (currentTime - timestamp > _MAX_CACHE_AGE_MS) {
          keysToRemove.add(key);
          expiredCount++;
        } else {
          // Update validation status for cached entries
          if (value['validUntil'] == null) {
            // Add validUntil timestamp (7 days from creation)
            value['validUntil'] = timestamp + _MAX_CACHE_AGE_MS;
          }
        }
      } else {
        // Add timestamp for entries without one
        value['_timestamp'] = currentTime;
        value['validUntil'] = currentTime + _MAX_CACHE_AGE_MS;
      }
    });
    
    for (final key in keysToRemove) {
      _prescriptionCache.remove(key);
    }
    
    if (expiredCount > 0) {
      print('Cache cleanup: Removed $expiredCount expired prescription cache entries');
    }
  }

  @override
  _PrescriptionScannerScreenState createState() => _PrescriptionScannerScreenState();
}

class _PrescriptionScannerScreenState extends State<PrescriptionScannerScreen> 
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final DrugApiService _drugApiService = DrugApiService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String get GEMINI_API_KEY => dotenv.env['GEMINI_API_KEY'] ?? '';
  static String get GEMINI_API_URL => dotenv.env['GEMINI_API_URL'] ?? '';
  String _resolveGeminiEndpoint() {
    final trimmed = GEMINI_API_URL.trim();
    if (trimmed.isEmpty) {
      return PrescriptionScannerScreen._DEFAULT_GEMINI_ENDPOINT;
    }

    if (trimmed.contains(':generateContent')) {
      return trimmed;
    }

    if (trimmed.endsWith('/')) {
      return '${trimmed.substring(0, trimmed.length - 1)}:generateContent';
    }

    return '$trimmed:generateContent';
  }
  
  File? _image;
  String _extractedText = '';
  bool _isProcessing = false;
  Map<String, dynamic> _extractedData = {};
  double _confidence = 0.0;
  String _processingStatus = 'Ready to scan';
  
  // Patient data for adherence tracking
  Map<String, dynamic>? _patient;
  
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCapturing = false;
  bool _showCameraPreview = true;
  bool _hasCameraPermission = false;
  
  String? _currentPreviewHash;
  bool _isCurrentlyInCache = false;
  Timer? _cacheCheckTimer;
  Timer? _cacheCleanupTimer;
  int? _cacheErrorCount;

  @override
  void initState() {
    super.initState();
    _checkAndInitializeCamera();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 2000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
    
    _startCacheChecking();
    _startCacheCleanup();
    
    // Add app lifecycle state observer
    WidgetsBinding.instance.addObserver(this as WidgetsBindingObserver);
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    if (state == AppLifecycleState.inactive || 
        state == AppLifecycleState.paused || 
        state == AppLifecycleState.detached) {
      // App is not active, pause camera to save resources
      _pauseCamera();
    } else if (state == AppLifecycleState.resumed) {
      // App is active again, resume camera if preview is visible
      if (_showCameraPreview && mounted) {
        _resumeCamera();
      }
    }
  }
  
  Future<void> _pauseCamera() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    
    try {
      // Stop the image stream if any
      try {
        await _cameraController!.stopImageStream();
      } catch (e) {
        // Ignore if there's no stream
        print('Note: No image stream to stop: $e');
      }
      
      print('Camera paused to save battery and resources');
    } catch (e) {
      print('Error pausing camera: $e');
    }
  }
  
  Future<void> _resumeCamera() async {
    if (_cameraController == null) {
      // Need to initialize camera
      await _initializeCamera();
      return;
    }
    
    if (!_cameraController!.value.isInitialized) {
      // Camera needs to be re-initialized
      try {
        await _cameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
        
        // Reset zoom level when camera is resumed
        await _cameraController!.setZoomLevel(1.0);
      } catch (e) {
        print('Error re-initializing camera: $e');
        // Try full initialization if failed
        await _initializeCamera();
      }
    } else {
      // Reset zoom level when camera is resumed
      try {
        await _cameraController!.setZoomLevel(1.0);
      } catch (e) {
        print('Error resetting zoom level: $e');
      }
    }
    
    print('Camera resumed and ready to use');
  }

  void _startCacheCleanup() {
    // Perform more frequent cleanups to ensure 7-day validation is enforced
    _cacheCleanupTimer = Timer.periodic(Duration(hours: 6), (timer) {
      // Run cache maintenance tasks
      print('Performing scheduled prescription cache maintenance');
      PrescriptionScannerScreen._removeExpiredEntries();
      PrescriptionScannerScreen._limitCacheSize();
      
      // Log cache stats
      final cacheSize = PrescriptionScannerScreen._prescriptionCache.length;
      if (cacheSize > 0) {
        print('Current prescription cache size: $cacheSize entries');
      }
    });
    
    // Initial cleanup on startup
    PrescriptionScannerScreen._removeExpiredEntries();
  }

  Future<void> _checkAndInitializeCamera() async {
    try {
      final status = await Permission.camera.request();
      setState(() => _hasCameraPermission = status.isGranted);
      
      if (status.isGranted) {
        // Initialize camera if permissions granted
        await _initializeCamera();
      } else {
        setState(() {
          _showCameraPreview = false;
          _processingStatus = 'Camera permission required';
        });
      }
    } catch (e) {
      print('Error checking camera permission: $e');
      setState(() {
        _showCameraPreview = false;
        _processingStatus = 'Error initializing camera';
      });
    }
  }

  Future<void> _initializeCamera() async {
    // Check if camera is already initialized and is in valid state
    if (_cameraController != null && 
        _cameraController!.value.isInitialized && 
        _isCameraInitialized) {
      print('Camera already initialized, skipping initialization');
      return;
    }
    
    try {
      // Show loading indicator
      setState(() => _processingStatus = 'Initializing camera...');
      
      // Dispose of any existing controller to free resources
      if (_cameraController != null) {
        await _cameraController?.dispose();
        _cameraController = null;
      }
      
      // Get available cameras with timeout to prevent hanging
      _cameras = await availableCameras().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('Camera discovery timeout');
          throw TimeoutException('Camera discovery timed out');
        }
      );
      
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _showCameraPreview = false;
          _processingStatus = 'No cameras available';
          _isCameraInitialized = false;
        });
        return;
      }
      
      // Try to select the back camera first
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      // Create controller with high resolution for better quality
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.max, // Using maximum resolution for best image quality
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Initialize with timeout
      await _cameraController!.initialize().timeout(
        Duration(seconds: 10),
        onTimeout: () {
          print('Camera initialization timeout');
          throw TimeoutException('Camera initialization timed out');
        }
      );
      
      // Configure for highest quality
      if (_cameraController!.value.isInitialized) {
        try {
          // The camera is already initialized with ResolutionPreset.max
          // which is the highest resolution available
          print('Camera initialized with max resolution preset');
          
          // Set max zoom level to 1.0 to disable zooming
          await _cameraController!.setZoomLevel(1.0);
        } catch (e) {
          print('Error configuring camera quality: $e');
          // Continue even if setting quality fails
        }
      }
      
      // Setting exposure and focus modes for better scanning
      if (_cameraController!.value.isInitialized) {
        try {
          // Briefly use auto focus and exposure, then lock
          await _cameraController!.setFlashMode(FlashMode.off);
          await _cameraController!.setFocusMode(FocusMode.auto);
          await _cameraController!.setExposureMode(ExposureMode.auto);
        } catch (e) {
          print('Error setting camera modes: $e');
          // Continue even if setting modes fails
        }
      }
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = _cameraController?.value.isInitialized ?? false;
          _showCameraPreview = _isCameraInitialized;
          _processingStatus = _isCameraInitialized ? 'Ready to scan' : 'Camera initialization failed';
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
      
      // Try to recover - dispose controller if failed
      try {
        await _cameraController?.dispose();
      } catch (_) {}
      _cameraController = null;
      
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
          _showCameraPreview = false;
          _processingStatus = 'Error initializing camera: ${e.toString().split(':').first}';
        });
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: ${e.toString().split(':').first}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      // Only handle gallery source - camera is handled directly
      if (source != ImageSource.gallery) return;
      
      setState(() {
        _isCapturing = false;
        _showCameraPreview = false;
      });
      
      // Stop camera to save resources when using gallery
      _pauseCamera();

      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 100, // Maximum quality
        // Remove max dimensions to get full resolution
        preferredCameraDevice: CameraDevice.rear, // Use rear camera for better quality
      );

      if (image != null) {
        setState(() {
          _image = File(image.path);
          _isProcessing = true;
          _extractedText = '';
          _extractedData = {};
          _confidence = 0.0;
          _processingStatus = 'Processing with MedicFood AI...';
          _showCameraPreview = false;
        });
        await _processImageWithGemini();
      }
    } catch (e) {
      print('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _processImageWithGemini() async {
    if (_image == null) return;

    try {
      if (GEMINI_API_KEY.isEmpty) {
        throw Exception('Missing Gemini API key');
      }

      setState(() => _processingStatus = 'Analyzing prescription...');
      
      final bytes = await _image!.readAsBytes();
      final imageHash = sha256.convert(bytes).toString();
      
      // Clean up expired cache entries
      PrescriptionScannerScreen._removeExpiredEntries();
      
      // Check if image is in cache and not expired
      if (PrescriptionScannerScreen._prescriptionCache.containsKey(imageHash)) {
        final cachedResult = PrescriptionScannerScreen._prescriptionCache[imageHash]!;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        
        // Update last accessed timestamp
        cachedResult['_timestamp'] = currentTime;
        
        // Check if cache entry is still valid
        final validUntil = cachedResult['validUntil'] as int? ?? 
                          (cachedResult['_timestamp'] as int? ?? currentTime) + PrescriptionScannerScreen._MAX_CACHE_AGE_MS;
        
        if (currentTime <= validUntil) {
          // Hide cache-related status from user
          setState(() => _processingStatus = 'Processing your prescription...');
          
          // Small artificial delay to avoid UI flashing
          await Future.delayed(Duration(milliseconds: 500));
          
          setState(() {
            _extractedData = cachedResult;
            _extractedText = _formatExtractedData(cachedResult);
            _confidence = 0.99; // High confidence for cached results
            _isProcessing = false;
            _processingStatus = 'Processing complete';
          });
          return;
        }
        // Cache expired, remove it
        PrescriptionScannerScreen._prescriptionCache.remove(imageHash);
      }
      
      // Don't tell user it's not in cache - just show processing message
      setState(() => _processingStatus = 'Analyzing with MedicFood AI...');
      
      final base64Image = base64Encode(bytes);

      final prompt = '''
      Analyze this prescription image and convert to JSON:
      Rules: Convert t→tablet, c→capsule/relevant,1-0-1→morning&night, 1-0-0→morning, 0-0-1→night, 1-1-1→morning & afternoon & night
        "diagnosis": "string (if visible on prescription)",
        "medicines": [
          {
            "name": "correct medicine name full form",
            "type": "tablet/capsule/syrup/injection/etc",
            "dosage": "amount+unit(mg/etc)",
            "timing": "morning/afternoon/night or combinations with &",
            "duration": "number of days(example:2 days/1month) ",
            "instructions": "before/after food, etc"
          }
        ],
        "additionalInstructions": ""
      }''';
      
      final requestBody = {
        "contents": [
          {
            "parts": [
              {"text": prompt},
              {
                "inline_data": {
                  "mime_type": "image/jpeg",
                  "data": base64Image
                }
              }
            ]
          }
        ],
        "generationConfig": {
          "temperature": 0.1,
          "topK": 32,
          "topP": 0.95,
          "maxOutputTokens": 6000,
        },
      };

      setState(() => _processingStatus = 'Processing Image...');

      final resolvedEndpoint = _resolveGeminiEndpoint();
      final response = await http.post(
        Uri.parse('$resolvedEndpoint?key=$GEMINI_API_KEY'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        setState(() => _processingStatus = 'Almost Ready...');
        
        final responseData = jsonDecode(response.body);
        final generatedText = responseData['candidates'][0]['content']['parts'][0]['text'];
        
        final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(generatedText);
        if (jsonMatch != null) {
          final extractedJson = jsonDecode(jsonMatch.group(0)!);
          
          setState(() => _processingStatus = 'Validating medicines...');
          
          await _validateMedicinesWithDrugAPI(extractedJson);
          
          // Add metadata for cache validation
          final currentTime = DateTime.now().millisecondsSinceEpoch;
          extractedJson['id'] = currentTime.toString();
          extractedJson['_timestamp'] = currentTime;
          extractedJson['validUntil'] = currentTime + PrescriptionScannerScreen._MAX_CACHE_AGE_MS;
          extractedJson['cacheVersion'] = 2; // Cache version for future compatibility
          
          // Store in cache with 7-day validation
          PrescriptionScannerScreen._prescriptionCache[imageHash] = extractedJson;
          
          // Manage cache size and remove expired entries
          PrescriptionScannerScreen._limitCacheSize();
          PrescriptionScannerScreen._removeExpiredEntries();
          
          setState(() {
            _extractedData = extractedJson;
            _extractedText = _formatExtractedData(extractedJson);
            _confidence = 0.99;
            _isProcessing = false;
            _processingStatus = 'Processing complete';
          });
        } else {
          throw Exception('Could not parse JSON from MedicFood response');
        }
      } else {
        final errorMessage = _extractGeminiErrorMessage(response.body);
        throw Exception('MedicFood AI failed with status ${response.statusCode}${errorMessage.isNotEmpty ? ': $errorMessage' : ''}');
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingStatus = 'Error: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing prescription: $e')),
      );
    }
  }

  String _extractGeminiErrorMessage(String responseBody) {
    if (responseBody.isEmpty) {
      return '';
    }
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is Map<String, dynamic>) {
        if (decoded['error'] is Map<String, dynamic>) {
          final error = decoded['error'] as Map<String, dynamic>;
          final message = error['message']?.toString() ?? '';
          final status = error['status']?.toString() ?? '';
          return [status, message].where((part) => part.isNotEmpty).join(' - ');
        }

        // For Gemini responses that use 'candidates' only when successful, fall back to string.
        return decoded['message']?.toString() ?? decoded['error_message']?.toString() ?? '';
      }
      return responseBody;
    } catch (_) {
      return responseBody;
    }
  }

  Future<void> _validateMedicinesWithDrugAPI(Map<String, dynamic> extractedData) async {
    if (extractedData['medicines'] != null) {
      for (var medicine in extractedData['medicines']) {
        try {
          String nameToValidate = medicine['name'] ?? '';
          final originalType = medicine['type']?.toLowerCase() ?? 'tablet';
          
          // Pass medicine type to the validateDrug method for better matching
          final validation = await _drugApiService.validateDrug(
            nameToValidate,
            medicineType: originalType,
          );
          
          medicine['validated'] = validation['isValid'] ?? false;
          medicine['rxcui'] = validation['rxcui'] ?? '';
          medicine['drugDetails'] = validation['details'] ?? {};
          medicine['originalName'] = validation['originalName'];
          medicine['correctedName'] = validation['correctedName'];
          medicine['wasCorrected'] = validation['wasCorrected'] ?? false;
          medicine['confidence'] = validation['confidence'] ?? 0.7;
          medicine['correctionMethod'] = validation['correctionMethod'] ?? 'none';
          medicine['alternatives'] = validation['alternativeSuggestions'] ?? [];
          medicine['typeMatchSuccess'] = validation['matchedType'] ?? false;
          
          if (validation['details']?.containsKey('form') == true) {
            medicine['type'] = validation['details']['form'];
          } else if (originalType != 'tablet') {
            medicine['type'] = originalType;
          }
          
          medicine['type'] = medicine['type'][0].toUpperCase() + medicine['type'].substring(1);
          
          if (medicine['wasCorrected'] == true && medicine['confidence'] > 0.8) {
            medicine['name'] = medicine['correctedName'];
          }
          
          String timing = medicine['timing'] ?? '';
          medicine['frequency'] = _calculateFrequencyFromTiming(timing);
          
        } catch (e) {
          print('Error validating medicine: $e');
          medicine['validated'] = false;
          medicine['confidence'] = 0.6;
          medicine['wasCorrected'] = false;
          medicine['correctionMethod'] = 'error';
          medicine['type'] = medicine['type'] ?? 'Tablet';
        }
      }
    }
  }

  String _calculateFrequencyFromTiming(String timing) {
    final timingParts = timing.toLowerCase().split(' & ');
    switch (timingParts.length) {
      case 1:
        return 'Once Daily';
      case 2:
        return 'Twice Daily';
      case 3:
        return 'Three Times Daily';
      case 4:
        return 'Four Times Daily';
      default:
        return 'Once Daily';
    }
  }

  String _formatExtractedData(Map<String, dynamic> data) {
    final cleanData = Map<String, dynamic>.from(data);
    cleanData.remove('_timestamp');
    
    String result = '';

    if (cleanData['diagnosis']?.isNotEmpty == true) {
      result += 'Diagnosis: ${cleanData['diagnosis']}\n';
    }

    if (cleanData['medicines']?.isNotEmpty == true) {
      result += '\nMedicines:\n';
      for (var medicine in cleanData['medicines']) {
        result += '• ${medicine['name']}';
        if (medicine['dosage']?.isNotEmpty == true) {
          result += ' ${medicine['dosage']}\n';
        }
        result += '\n';
        if (medicine['timing']?.isNotEmpty == true) {
          result += '  Timing: ${medicine['timing']}\n';
        }
        if (medicine['duration']?.isNotEmpty == true) {
          result += '  Duration: ${medicine['duration']}\n';
        }
        if (medicine['instructions']?.isNotEmpty == true) {
          result += '  Instructions: ${medicine['instructions']}\n';
        }
      }
    }

    if (cleanData['additionalInstructions']?.isNotEmpty == true) {
      result += '\nAdditional Instructions: ${cleanData['additionalInstructions']}\n';
    }

    return result.isEmpty ? 'No prescription data detected. Please try again with better lighting or a clearer image.' : result;
  }

  @override
  Widget build(BuildContext context) {
    // Ensure camera is paused when widget is not visible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_showCameraPreview && _cameraController != null && _cameraController!.value.isInitialized) {
        _pauseCamera();
      }
    });
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Prescription Scanner',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF6B46C1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.document_scanner_outlined, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Camera preview or prescription scanning area
            Container(
              padding: _showCameraPreview ? EdgeInsets.symmetric(vertical: 16) : EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50, // Reverted back to original green color
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showCameraPreview)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.green.shade600, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Powered by MedicFood AI',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.auto_awesome, color: Colors.green.shade600, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Powered by MedicFood AI',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                  SizedBox(height: _showCameraPreview ? 12 : 8),
                  
                  // Camera preview
                  if (_image == null && _showCameraPreview) 
                    _buildCameraPreview(),
                  
                  if (!_showCameraPreview && _image == null)
                    Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt, size: 48, color: Colors.grey.shade500),
                            SizedBox(height: 16),
                            Text(
                              'Tap "Take Photo" to scan a prescription',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  // Instruction text - only show if camera preview is visible
                  if (_showCameraPreview && _image == null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4, left: 16, right: 16),
                      child: Text(
                        '• Align prescription paper within purple box\n• Hold phone flat and steady above document\n• Ensure all text is clearly visible and tap to capture',
                        style: TextStyle(color: Colors.green.shade800, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ] else if (_image == null) ...[
                    SizedBox(height: 12),
                    Text(
                      '• Use "Take Photo" to scan a standard prescription\n• Ensure good lighting for best results',
                      style: TextStyle(color: Colors.green.shade700, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 20),

            // Separate buttons for Take Photo and Upload Image
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            // Take photo using camera
                            await _captureImage();
                          },
                    icon: Icon(Icons.camera_alt, color: Colors.white),
                    label: Text('Take Photo', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple.shade400,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () async {
                            // Upload image from gallery
                            await _pickImage(ImageSource.gallery);
                          },
                    icon: Icon(Icons.upload_file, color: Colors.white),
                    label: Text('Upload Image', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade400,
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 20),

            // Adherence tracking widget removed as per request.

            if (_isProcessing) ...[
              Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B46C1)),
                    ),
                    SizedBox(height: 16),
                    Text(
                      _processingStatus,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scanning...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
            ],

            if (_extractedText.isNotEmpty && !_isProcessing) ...[
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _confidence > 0.9 ? Colors.green[100] : 
                         _confidence > 0.7 ? Colors.orange[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _confidence > 0.9 ? Icons.check_circle : 
                      _confidence > 0.7 ? Icons.warning : Icons.error,
                      color: _confidence > 0.9 ? Colors.green : 
                             _confidence > 0.7 ? Colors.orange : Colors.red,
                    ),
                    SizedBox(width: 8),
                    Text('AI Accuracy: ${(_confidence * 100).toStringAsFixed(1)}%'),
                  ],
                ),
              ),
              SizedBox(height: 16),

              Text(
                'Extracted Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_extractedData['diagnosis']?.isNotEmpty == true) ...[
                      _buildInfoRow('Diagnosis:', _extractedData['diagnosis']),
                      SizedBox(height: 8),
                    ],

                    if (_extractedData['medicines']?.isNotEmpty == true) ...[
                      Text(
                        'Medicines:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      SizedBox(height: 8),
                      ..._extractedData['medicines'].map<Widget>((medicine) =>
                        Container(
                          margin: EdgeInsets.only(bottom: 8),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Color(0xFF6B46C1).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${medicine['name']} ${medicine['dosage'] ?? ''}${medicine['unit'] ?? ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6B46C1),
                                      ),
                                    ),
                                  ),
                                  if (medicine['validated'] == true)
                                    Icon(Icons.verified, color: Colors.green, size: 16),
                                ],
                              ),
                              if (medicine['type'] != null)
                                Text(
                                  'Type: ${medicine['type']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              if (medicine['timing']?.isNotEmpty == true)
                                Text(
                                  'Timing: ${medicine['timing']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              if (medicine['duration']?.isNotEmpty == true)
                                Text(
                                  'Duration: ${medicine['duration']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              if (medicine['instructions']?.isNotEmpty == true)
                                Text(
                                  'Instructions: ${medicine['instructions']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              Row(
                                children: [
                                  Text(
                                    'Confidence: ${((medicine['confidence'] ?? 0.0) * 100).toInt()}% | ',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  Text(
                                    '${medicine['validated'] == true ? 'Validated' : 'Unvalidated'}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: medicine['validated'] == true ? Colors.green.shade700 : Colors.grey.shade600,
                                    ),
                                  ),
                                  if (medicine['typeMatchSuccess'] == true)
                                    Text(
                                      ' | Type Match ✓',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ).toList(),
                    ],

                    if (_extractedData['additionalInstructions']?.isNotEmpty == true) ...[
                      SizedBox(height: 12),
                      _buildInfoRow('Additional Instructions:', _extractedData['additionalInstructions']),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _processExtractedText();
                      },
                      icon: Icon(Icons.add_circle, color: Colors.white),
                      label: Text('Add to Schedule', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade400,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        setState(() {
                          _image = null;
                          _extractedText = '';
                          _extractedData = {};
                          _confidence = 0.0;
                          _processingStatus = 'Ready to scan';
                          _showCameraPreview = true;
                        });
                        // Resume camera when scanning again
                        await _resumeCamera();
                      },
                      icon: Icon(Icons.refresh, color: Colors.white),
                      label: Text('Scan Again', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade400,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(String text, IconData icon, Color color, VoidCallback onPressed) {
    // Special handling for camera action
    if (text == 'Take Photo') {
      return ElevatedButton.icon(
        onPressed: () async {
          // If camera not initialized, initialize it first
          if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Starting camera...'),
                duration: Duration(seconds: 2),
              ),
            );
            
            try {
              await _checkAndInitializeCamera();
              
              // Wait for camera to initialize fully
              if (!_isCameraInitialized && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Camera initialization failed. Trying again...'),
                    duration: Duration(seconds: 2),
                  ),
                );
                await Future.delayed(Duration(seconds: 1));
                await _initializeCamera(); // Try again
                
                if (!_isCameraInitialized && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please restart the app if camera issues persist'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
              }
            } catch (e) {
              print('Camera initialization error: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not access camera. Please check permissions.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
          }
          
          // Instead of just showing the preview, directly capture photo
          await _captureImage();
        },
        icon: Icon(icon, color: Colors.white),
        label: Text(text, style: TextStyle(color: Colors.white, fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
    
    // Default handling for other actions
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white),
      label: Text(text, style: TextStyle(color: Colors.white, fontSize: 14)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _processExtractedText() {
    if (_extractedData['medicines']?.isNotEmpty == true) {
      final cleanData = Map<String, dynamic>.from(_extractedData);
      cleanData.remove('_timestamp');
      
      // Process all prescription medicines (not just validated ones)
      List<dynamic> allMedicines = _extractedData['medicines'];
      
      // Mark each medicine as from prescription
      for (var medicine in allMedicines) {
        medicine['is_from_prescription'] = true;
      }
      
      // Call the original callback with the processed data
      widget.onPrescriptionScanned?.call(cleanData);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No medicines found to add to schedule'),
          backgroundColor: Colors.orange.shade400,
        ),
      );
    }
  }
  
  // Convert prescription medicines to Medicine objects
  
  @override
  void dispose() {
    // Remove observer
    WidgetsBinding.instance.removeObserver(this as WidgetsBindingObserver);
    
    // Stop camera and release resources
    if (_cameraController != null) {
      _cameraController!.stopImageStream().catchError((e) => print('Error stopping stream: $e'))
        .then((_) {
          _cameraController!.dispose();
          print('Camera disposed successfully');
        }).catchError((e) => print('Error disposing camera: $e'));
    }
    
    // Dispose animation controller
    _animationController.dispose();
    
    // Cancel all timers
    _cacheCheckTimer?.cancel();
    _cacheCleanupTimer?.cancel();
    
    print('PrescriptionScannerScreen disposed and resources released');
    super.dispose();
  }

  Widget _buildCameraPreview() {
    if (!_hasCameraPermission) {
      return Container(
        height: 500,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_photography, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Camera permission required',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _checkAndInitializeCamera,
              child: Text('Grant Permission'),
            ),
          ],
        ),
      );
    }

    if (!_isCameraInitialized || _cameraController == null || !_cameraController!.value.isInitialized) {
      return Container(
        height: 500,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B46C1)),
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    
    // Use full width minus container padding
    final availableWidth = size.width - 32;
    // Taller height to better match standard document aspect ratio (A4/letter size)
    final previewHeight = 500.0;
    
    // Calculate camera transform scale to cover the container
    final cameraRatio = _cameraController!.value.aspectRatio;
    final screenRatio = availableWidth / previewHeight;
    
    // Improved scaling calculation to preserve quality
    final scale = cameraRatio > screenRatio
        ? previewHeight / (availableWidth / cameraRatio)
        : availableWidth / (previewHeight * cameraRatio);
    
    return Container(
      width: availableWidth,
      height: previewHeight,
      decoration: BoxDecoration(
        color: Colors.black, // Dark background for better contrast
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: GestureDetector(
          onTap: _captureImage,
          child: Stack(
            children: [
              // Camera preview with improved quality and positioning
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: availableWidth,
                    height: availableWidth / cameraRatio,
                    child: GestureDetector(
                      // Prevent zooming by ignoring scale gestures
                      onScaleStart: (_) {},
                      onScaleUpdate: (_) {},
                      onScaleEnd: (_) {},
                      child: CameraPreview(_cameraController!),
                    ),
                  ),
                ),
              ),
              
              // Capture overlay
              if (_isCapturing)
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera, color: Colors.white, size: 48),
                        SizedBox(height: 16),
                        Text(
                          'Capturing...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
              // Prescription outline - taller rectangle to match document proportions
              Center(
                child: Container(
                  width: availableWidth * 0.85,
                  // Adjust height to match typical document proportions (more rectangular)
                  height: previewHeight * 0.85,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Color(0xFF6B46C1),
                      width: 3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              
              // Corner guides
              ...List.generate(4, (index) {
                final isTop = index < 2; 
                final isLeft = index.isEven;
                
                return Positioned(
                  top: isTop ? 10 : null,
                  bottom: !isTop ? 10 : null,
                  left: isLeft ? 10 : null,
                  right: !isLeft ? 10 : null,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      border: Border(
                        top: isTop ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
                        bottom: !isTop ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
                        left: isLeft ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
                        right: !isLeft ? BorderSide(color: Colors.white, width: 3) : BorderSide.none,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _startCacheChecking() {
    // Prevent multiple timers
    _cacheCheckTimer?.cancel();
    _cacheErrorCount = 0;
    
    // Use a longer interval to reduce camera contention
    _cacheCheckTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (_isCameraInitialized && 
          _cameraController != null && 
          _cameraController!.value.isInitialized && 
          mounted && 
          !_isCapturing && 
          !_isProcessing) {
        _checkPreviewAgainstCache();
      }
    });
  }
  
  Future<void> _checkPreviewAgainstCache() async {
    try {
      // Don't try to take pictures if camera is not ready or is already capturing
      if (!_cameraController!.value.isInitialized || 
          _isCapturing || 
          _isProcessing ||
          !mounted) {
        return;
      }
      
      // Take a snapshot for cache checking
      final XFile snapshot = await _cameraController!.takePicture().timeout(
        Duration(seconds: 3),
        onTimeout: () {
          throw TimeoutException('Cache preview snapshot timed out');
        }
      );
      
      final bytes = await File(snapshot.path).readAsBytes();
      
      final previewHash = sha256.convert(bytes).toString();
      _currentPreviewHash = previewHash;
      
      // Check if image is in cache and still valid (but don't show to user)
      final isInCache = PrescriptionScannerScreen._prescriptionCache.containsKey(previewHash);
      if (isInCache) {
        final cachedData = PrescriptionScannerScreen._prescriptionCache[previewHash]!;
        final currentTime = DateTime.now().millisecondsSinceEpoch;
        final validUntil = cachedData['validUntil'] as int? ??
                           (cachedData['_timestamp'] as int? ?? 0) + PrescriptionScannerScreen._MAX_CACHE_AGE_MS;
                           
        // Only mark as cached if it's still valid
        _isCurrentlyInCache = currentTime <= validUntil;
      } else {
        _isCurrentlyInCache = false;
      }
      
      // Always clean up temporary files
      try {
        await File(snapshot.path).delete();
      } catch (e) {
        print('Error deleting temp file: $e');
      }
    } catch (e) {
      print('Error checking preview against cache: $e');
      _isCurrentlyInCache = false;
      
      // If we get repeated errors, stop the cache checking timer
      _cacheErrorCount = (_cacheErrorCount ?? 0) + 1;
      if ((_cacheErrorCount ?? 0) > 3) {
        _cacheCheckTimer?.cancel();
        _cacheCheckTimer = null;
        print('Disabled cache checking due to repeated errors');
      }
    }
  }

  Future<void> _captureImage() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera not ready. Please try again.')),
      );
      return;
    }
    
    if (_isCapturing) {
      // Prevent multiple simultaneous captures
      return;
    }
    
    try {
      setState(() {
        _isCapturing = true;
        _processingStatus = 'Capturing...';
      });
      
      // Reset focus and exposure before capturing to avoid issues
      try {
        // Use a more reliable capturing approach
        await Future.delayed(Duration(milliseconds: 100));
        
        // Configure for maximum quality capture
        await _cameraController!.setFlashMode(FlashMode.auto);
        
        // Set focus mode to auto first to let camera find optimal focus
        await _cameraController!.setFocusMode(FocusMode.auto);
        await _cameraController!.setExposureMode(ExposureMode.auto);
        
        // Reset zoom level to ensure no zoom is applied
        await _cameraController!.setZoomLevel(1.0);
        
        // Pause longer to allow camera to adjust properly for best quality
        await Future.delayed(Duration(milliseconds: 800));
        
        // Lock focus and exposure after auto-adjustment for consistent capture
        await _cameraController!.setFocusMode(FocusMode.locked);
        await _cameraController!.setExposureMode(ExposureMode.locked);
        
        // Additional pause to ensure settings are applied
        await Future.delayed(Duration(milliseconds: 200));
      } catch (e) {
        print('Error setting camera capture parameters: $e');
        // Continue with capture even if settings fail
      }
      
      // Use a brief delay to show the capture animation
      await Future.delayed(Duration(milliseconds: 200));
      
      // Capture with safeguards
      late final XFile capturedImage;
      try {
        // Take the picture with highest quality settings
        capturedImage = await _cameraController!.takePicture(
          // The camera plugin automatically uses the highest quality available
        ).timeout(
          Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Camera capture timed out');
          },
        );
        
        print('Image captured successfully at: ${capturedImage.path}');
        
      } catch (e) {
        print('Error during takePicture(): $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Capture failed. Trying again...'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          // Wait a moment, then retry once with simpler settings
          await Future.delayed(Duration(milliseconds: 500));
          try {
            // Reset camera settings for retry
            await _cameraController!.setFocusMode(FocusMode.auto);
            await _cameraController!.setExposureMode(ExposureMode.auto);
            
            // Take picture with highest quality settings
            capturedImage = await _cameraController!.takePicture();
            print('Image captured on retry at: ${capturedImage.path}');
          } catch (retryError) {
            print('Retry capture error: $retryError');
            throw Exception('Camera capture failed after retry');
          }
        } else {
          throw Exception('Camera capture failed');
        }
      }
      
      // Verify the image was captured successfully
      final imageFile = File(capturedImage.path);
      if (!await imageFile.exists() || await imageFile.length() == 0) {
        throw Exception('Captured image file is invalid or empty');
      }
      
      // Process the picture
      setState(() {
        _image = imageFile;
        _isProcessing = true;
        _extractedText = '';
        _extractedData = {};
        _confidence = 0.0;
        _processingStatus = 'Processing prescription...';
        _showCameraPreview = false;
      });
      
      // Stop camera to save battery while processing image
      await _pauseCamera();
      
      await _processImageWithGemini();
    } catch (e) {
      print('Error capturing image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error capturing image: ${e.toString().split(':').first}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      setState(() {
        _isCapturing = false;
        _isProcessing = false;
      });
      
      // Reset camera controller if we had an error
      try {
        await _initializeCamera();
      } catch (e) {
        print('Failed to reinitialize camera: $e');
      }
    } finally {
      // Always clear capturing state when done
      if (mounted) {
        setState(() => _isCapturing = false);
      }
      
      // Reset focus and exposure modes for next capture
      try {
        if (_cameraController != null && _cameraController!.value.isInitialized) {
          await _cameraController!.setFocusMode(FocusMode.auto);
          await _cameraController!.setExposureMode(ExposureMode.auto);
        }
      } catch (e) {
        print('Error resetting camera modes: $e');
      }
    }
  }

  Widget _buildAdherenceTrackingWidget() {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // Check if user is authenticated
        if (authService.userDetails == null) {
          return SizedBox.shrink(); // Don't show adherence widget if not authenticated
        }
        
        final String patientId = authService.userDetails!.id;
    
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users')
          .doc(patientId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .snapshots(),
      builder: (context, scheduleSnapshot) {
        int taken = 0;
        int total = 0;
        
        if (scheduleSnapshot.hasData && scheduleSnapshot.data!.exists) {
          final scheduleData = scheduleSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
          
          // Count total medicines and completed ones for today
          final today = DateTime.now().toIso8601String().split('T')[0];
          
          for (var medicineSchedule in medicines.values) {
            final medicine = medicineSchedule as Map<String, dynamic>? ?? {};
            final scheduleDataList = List<Map<String, dynamic>>.from(medicine['scheduleData'] ?? []);
            
            for (var schedule in scheduleDataList) {
              if (schedule['date'] == today) {
                total++;
                if (schedule['isCompleted'] == true) {
                  taken++;
                }
              }
            }
          }
        }
        
        // Only show the widget if there are medicines to track
        if (total == 0) {
          return SizedBox.shrink();
        }
        
        final adherencePercentage = total > 0 ? (taken / total * 100).round() : 0;
        
        return Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.medication, color: Colors.blue.shade600, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Today\'s Medicine Adherence',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$taken of $total taken',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '$adherencePercentage% adherence',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      value: total > 0 ? taken / total : 0.0,
                      strokeWidth: 6,
                      backgroundColor: Colors.blue.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        adherencePercentage >= 80 ? Colors.green :
                        adherencePercentage >= 60 ? Colors.orange : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
      },
    );
  }
}
