import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/medicine_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../utils/duration_helper.dart';
import '../utils/timing_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:flutter/services.dart';

class CardDetailScreen extends StatefulWidget {
  final String medicineName;
  final String? dosage;
  final String time;
  final String timing;
  final bool isFromPrescription;
  final Map<String, dynamic>? prescriptionData;
  final String? medicineId;
  final String type;
  final String frequency;
  final String instructions;
  final String foodInstructions;
  final bool isValidated;
  final String? scheduleDate;
  final String duration; // ADD THIS LINE

  const CardDetailScreen({
    Key? key,
    required this.medicineName,
    this.dosage,
    required this.time,
    required this.timing,
    this.isFromPrescription = false,
    this.prescriptionData,
    this.medicineId,
    this.type = 'Tablet',
    this.frequency = 'Once Daily',
    this.instructions = '',
    this.foodInstructions = 'Anytime',
    this.isValidated = false,
    this.scheduleDate,
    this.duration = '', // ADD THIS LINE
  }) : super(key: key);

  @override
  _CardDetailScreenState createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> with TickerProviderStateMixin {
  File? _frontImage;
  File? _backImage;
  final ImagePicker _picker = ImagePicker();
  
  String _selectedType = 'Tablet';
  String _selectedFrequency = 'Once Daily';
  String _selectedTiming = 'Morning';
  String _selectedFoodTiming = 'Anytime';
  TimeOfDay _selectedTime = TimeOfDay.now();
  
  final List<String> _medicineTypes = [
    'Tablet',
    'Capsule', 
    'Syrup',
    'Injection',
    'Drops',
    'Cream',
    'Inhaler',
    'Powder',
    'Gel',
    'Spray',
    'Patch',
    'Suppository'
  ];
  
  // Use centralized frequency options from TimingUtils
  List<String> get _frequencies => TimingUtils.getValidFrequencyOptions();
  
  // Use centralized timing options from TimingUtils
  List<String> get _timingOptions => TimingUtils.getValidTimingOptions() + ['Custom'];
  
  final List<String> _foodInstructions = [
    'Before Food',
    'After Food',
    'With Food',
    'Empty Stomach',
    'Anytime',
  ];

  // Medicine type icon mapping
  IconData _getMedicineTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'tablet':
        return Icons.medication_rounded;
      case 'capsule':
        return Icons.medication_liquid_rounded;
      case 'syrup':
        return Icons.water_drop_rounded;
      case 'injection':
        return Symbols.syringe_rounded;
      case 'drops':
        return Icons.opacity_rounded;
      case 'cream':
        return Icons.healing_rounded;
      case 'inhaler':
        return Icons.air_rounded;
      case 'powder':
        return Icons.grain_rounded;
      case 'gel':
        return Icons.water_rounded;
      case 'spray':
        return Icons.sanitizer_rounded;
      case 'patch':
        return Icons.medical_information_rounded;
      case 'suppository':
        return Icons.invert_colors_rounded;
      case 'lotion':
        return Icons.wash_rounded;
      case 'ointment':
        return Icons.format_paint_rounded;
      case 'solution':
        return Icons.local_drink_rounded;
      case 'device':
        return Icons.devices_rounded;
      case 'implant':
        return Icons.biotech_rounded;
      default:
        return Icons.medication_rounded;
    }
  }

  Map<String, List<TimeOfDay>> _defaultTimes = {
    'Morning': [TimeOfDay(hour: 8, minute: 0)],
    'Afternoon': [TimeOfDay(hour: 14, minute: 0)],
    'Night': [TimeOfDay(hour: 20, minute: 0)],
    'Morning & Afternoon': [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 14, minute: 0)],
    'Morning & Night': [TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 20, minute: 0)],
    'Afternoon & Night': [TimeOfDay(hour: 14, minute: 0), TimeOfDay(hour: 20, minute: 0)],
    'Morning & Afternoon & Night': [
      TimeOfDay(hour: 8, minute: 0),
      TimeOfDay(hour: 14, minute: 0),
      TimeOfDay(hour: 20, minute: 0)
    ]
  };

  List<TimeOfDay> _selectedTimes = [TimeOfDay(hour: 8, minute: 0)];
  
  late TextEditingController _medicineNameController;
  late TextEditingController _dosageController;
  late TextEditingController _instructionsController;
  late TextEditingController _durationController;
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  bool _isValidated = false;
  bool _isSaving = false;
  bool _isProcessingImage = false;
  bool _hasShownPermissionDialog = false;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isEditMode = false;
  
  // Add date range selection variables
  DateTime? _startDate;
  DateTime? _endDate;
  bool _useDateRange = false;
  
  // Voice recording variables
  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _voiceFilePath;
  Duration _recordingDuration = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize controllers with widget data
    _medicineNameController = TextEditingController(text: widget.medicineName);
    _dosageController = TextEditingController(text: widget.dosage ?? '');
    _instructionsController = TextEditingController(text: widget.instructions);
    _durationController = TextEditingController(text: widget.duration);
    
    _isEditMode = widget.medicineId != null;
    
    // Initialize all form fields consistently for both add and edit modes
    _initializeFormFields();
    
    // Set up animations
    _animationController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );
    
    _slideAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    // Initialize prescription data if applicable
    _initializeFromPrescription();
    
    // Only update frequency from timing if we don't have a specific frequency from widget
    // This prevents overwriting saved frequency with calculated frequency
    if (!widget.isFromPrescription && (widget.frequency.isEmpty || widget.frequency == 'Once Daily')) {
      _updateFrequencyFromTiming(_selectedTiming);
    }
    
    _animationController.forward();

    // Load existing medicine data if in edit mode
    if (_isEditMode && widget.medicineId != null) {
      print('🔍 Edit mode detected, loading medicine data from database...');
      _loadExistingMedicineData();
    }
    
    // Initialize date range with today as start date and default to calendar selection
    _startDate = TimingUtils.getToday();
    _endDate = TimingUtils.getTomorrow();
    _useDateRange = true; // Default to calendar selection
  }

  /// Initialize all form fields consistently for both add and edit modes
  void _initializeFormFields() {
    // Medicine type - ensure proper formatting
    _selectedType = _formatMedicineType(widget.type);
    
    // Timing - use widget timing or default to 'Morning'
    _selectedTiming = widget.timing.isNotEmpty ? widget.timing : 'Morning';
    
    // Food instructions - use widget data or default to 'Anytime'
    _selectedFoodTiming = widget.foodInstructions.isNotEmpty ? widget.foodInstructions : 'Anytime';
    
    // Frequency - use widget frequency or default to 'Once Daily'
    _selectedFrequency = widget.frequency.isNotEmpty ? widget.frequency : 'Once Daily';
    
    // Validation status
    _isValidated = widget.isValidated;
    
    // Initialize times based on timing
    _initializeTimesFromTiming();
    
    print('🔧 Initialized form fields:');
    print('  - Type: $_selectedType');
    print('  - Timing: $_selectedTiming');
    print('  - Food Instructions: $_selectedFoodTiming');
    print('  - Frequency: $_selectedFrequency');
    print('  - Times: ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
  }

  /// Initialize times based on the selected timing
  void _initializeTimesFromTiming() {
    if (_isEditMode) {
      // For edit mode, start with empty times - will be loaded from database
      _selectedTimes = [];
    } else {
      // For add mode, use default times based on timing
      _selectedTimes = _defaultTimes[_selectedTiming] ?? [TimeOfDay(hour: 8, minute: 0)];
      
      // If timing is 'Custom', ensure we have at least one time
      if (_selectedTiming == 'Custom' && _selectedTimes.isEmpty) {
        _selectedTimes = [TimeOfDay(hour: 8, minute: 0)];
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure duration and times are properly loaded when dependencies change
    if (_isEditMode && widget.medicineId != null) {
      // Add a small delay to ensure the medicine data is loaded
      Future.delayed(Duration(milliseconds: 100), () {
        if (mounted) {
          _refreshDurationFromDatabase();
          _refreshTimesFromDatabase();
        }
      });
    }
  }

  Future<void> _refreshDurationFromDatabase() async {
    if (!_isEditMode || widget.medicineId == null) return;
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final medicineService = MedicineService();
      
      if (authService.userDetails != null) {
        final medicineData = await medicineService.getMedicine(
          authService.userDetails!.id, 
          widget.medicineId!
        );
        
        if (medicineData != null && medicineData.containsKey('duration')) {
          final databaseDuration = medicineData['duration']?.toString() ?? '';
          if (databaseDuration != _durationController.text) {
            setState(() {
              _durationController.text = databaseDuration;
            });
            print('🔄 Refreshed duration from database: "$databaseDuration"');
          }
        }
      }
    } catch (e) {
      print('⚠️ Error refreshing duration: $e');
    }
  }

  Future<void> _refreshTimesFromDatabase() async {
    if (!_isEditMode || widget.medicineId == null) return;
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final medicineService = MedicineService();
      
      if (authService.userDetails != null) {
        final medicineData = await medicineService.getMedicineLocalFirst(
          authService.userDetails!.id, 
          widget.medicineId!
        );
        
        if (medicineData != null) {
          String? timeData = medicineData['time']?.toString();
          
          // Check multiple possible time fields
          if (timeData == null || timeData.isEmpty) {
            timeData = medicineData['mappedTime']?.toString();
          }
          if (timeData == null || timeData.isEmpty) {
            timeData = medicineData['reminderTime']?.toString();
          }
          
          if (timeData != null && timeData.isNotEmpty) {
            final parsedTimes = _parseTimesFromString(timeData);
            if (parsedTimes.isNotEmpty && !_areTimesEqual(_selectedTimes, parsedTimes)) {
              setState(() {
                _selectedTimes = parsedTimes;
              });
              print('🔄 Refreshed times from database: ${parsedTimes.map((t) => t.format(context)).join(', ')}');
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error refreshing times: $e');
    }
  }

  bool _areTimesEqual(List<TimeOfDay> times1, List<TimeOfDay> times2) {
    if (times1.length != times2.length) return false;
    for (int i = 0; i < times1.length; i++) {
      if (times1[i].hour != times2[i].hour || times1[i].minute != times2[i].minute) {
        return false;
      }
    }
    return true;
  }

  /// Sync frequency with the number of times to ensure consistency
  void _syncFrequencyWithTimes() {
    final timeCount = _selectedTimes.length;
    String newFrequency;
    
    // Check if times follow a specific interval pattern
    if (timeCount == 4 && _isIntervalPattern(_selectedTimes, 6)) {
      newFrequency = 'Every 6 Hours';
    } else if (timeCount == 4 && _isIntervalPattern(_selectedTimes, 4)) {
      newFrequency = 'Every 4 Hours';
    } else if (timeCount == 3 && _isIntervalPattern(_selectedTimes, 8)) {
      newFrequency = 'Every 8 Hours';
    } else if (timeCount == 2 && _isIntervalPattern(_selectedTimes, 12)) {
      newFrequency = 'Every 12 Hours';
    } else {
      // Standard frequency based on count
      switch (timeCount) {
        case 1:
          newFrequency = 'Once Daily';
          break;
        case 2:
          newFrequency = 'Twice Daily';
          break;
        case 3:
          newFrequency = 'Three Times Daily';
          break;
        case 4:
          newFrequency = 'Four Times Daily';
          break;
        default:
          newFrequency = 'Custom';
          break;
      }
    }
    
    if (_selectedFrequency != newFrequency) {
      setState(() {
        _selectedFrequency = newFrequency;
      });
      print('🔄 Synced frequency to: $newFrequency (based on $timeCount times)');
    }
  }

  /// Check if times follow a specific hour interval pattern
  bool _isIntervalPattern(List<TimeOfDay> times, int intervalHours) {
    if (times.length < 2) return false;
    
    // Sort times to ensure proper order
    final sortedTimes = List<TimeOfDay>.from(times);
    sortedTimes.sort((a, b) {
      final aMinutes = a.hour * 60 + a.minute;
      final bMinutes = b.hour * 60 + b.minute;
      return aMinutes.compareTo(bMinutes);
    });
    
    // Check if intervals are consistent
    for (int i = 1; i < sortedTimes.length; i++) {
      final prevTime = sortedTimes[i - 1];
      final currentTime = sortedTimes[i];
      
      // Calculate time difference in hours
      int prevMinutes = prevTime.hour * 60 + prevTime.minute;
      int currentMinutes = currentTime.hour * 60 + currentTime.minute;
      
      // Handle day boundary (e.g., 18:00 to 00:00)
      if (currentMinutes < prevMinutes) {
        currentMinutes += 24 * 60; // Add 24 hours
      }
      
      int diffHours = (currentMinutes - prevMinutes) ~/ 60;
      
      if (diffHours != intervalHours) {
        return false;
      }
    }
    
    return true;
  }

  String _formatMedicineType(String type) {
    if (type.isEmpty) return 'Tablet';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  void _updateFrequencyFromTiming(String timing) {
    List<TimeOfDay>? times = _defaultTimes[timing];
    if (times != null) {
      int count = times.length;
      String newFrequency;
      if (count == 1) {
        newFrequency = 'Once Daily';
      } else if (count == 2) {
        newFrequency = 'Twice Daily';
      } else if (count == 3) {
        newFrequency = 'Three Times Daily';
      } else if (count == 4) {
        newFrequency = 'Four Times Daily';
      } else {
        newFrequency = 'Once Daily';
      }
      
      if (_selectedFrequency != newFrequency) {
        setState(() {
          _selectedFrequency = newFrequency;
        });
        print('🔄 Updated frequency from timing "$timing": $newFrequency');
      }
    } else {
      setState(() => _selectedFrequency = 'Once Daily');
    }
  }

  /// Update timing based on frequency to ensure consistency
  void _updateTimingFromFrequency(String frequency) {
    String newTiming;
    
    // Use TimingUtils to parse frequency and determine timing
    final intervalHours = TimingUtils.parseFrequencyToHours(frequency);
    
    if (intervalHours == null) {
      // For invalid frequency
      newTiming = 'Custom';
    } else if (intervalHours >= 24) {
      // For daily or longer intervals
      newTiming = 'Morning';
    } else if (intervalHours == 12) {
      newTiming = 'Morning & Night';
    } else if (intervalHours == 8) {
      newTiming = 'Morning & Afternoon & Night';
    } else {
      // For sub-daily intervals (6 hours, 4 hours, 3 hours, 2 hours, 1 hour, etc.)
      // Use Custom timing since we removed "Every X Hours" from timing options
      newTiming = 'Custom';
    }
    
    if (_selectedTiming != newTiming) {
      setState(() {
        _selectedTiming = newTiming;
        // Update times to match the new timing
        if (newTiming == 'Custom') {
          // Generate times based on frequency
          _selectedTimes = TimingUtils.generateTimesFromFrequency(frequency);
        } else {
          _selectedTimes = _defaultTimes[newTiming] ?? [TimeOfDay(hour: 8, minute: 0)];
        }
        print('🔄 Updated times for frequency "$frequency": ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
      });
      print('🔄 Updated timing from frequency "$frequency": $newTiming');
    }
  }

  void _initializeFromPrescription() {
    if (widget.isFromPrescription && widget.prescriptionData != null) {
      final medicines = widget.prescriptionData!['medicines'] as List?;
      if (medicines != null && medicines.isNotEmpty) {
        final medicine = medicines.firstWhere(
          (m) => m['name'] == widget.medicineName,
          orElse: () => medicines.first,
        );
        
        setState(() {
          // Update controllers with prescription data
          _medicineNameController.text = medicine['name'] ?? widget.medicineName;
          _dosageController.text = medicine['dosage']?.toString() ?? '';
          _instructionsController.text = medicine['instructions'] ?? '';
          
          // Properly format medicine type
          String rawType = (medicine['type'] ?? medicine['form'] ?? 'Tablet').toString();
          _selectedType = _formatMedicineType(rawType);
          
          // Map timing from prescription
          String rawTiming = medicine['timing'] ?? 'Morning';
          String mappedTiming = TimingUtils.mapTimingFromPrescription(rawTiming);
          _selectedTiming = _timingOptions.contains(mappedTiming) ? mappedTiming : 'Morning';
          
          // Set frequency from prescription
          _selectedFrequency = medicine['frequency'] ?? TimingUtils.mapFrequencyFromPrescription(rawTiming);
          
          // Set food instructions
          String rawFoodInstructions = medicine['foodInstructions'] ?? 'Anytime';
          _selectedFoodTiming = (medicine['foodInstructions'] as String?)?.isNotEmpty == true ? medicine['foodInstructions'] : 'Anytime';
          
          // Set validation status
          _isValidated = medicine['validated'] ?? false;
          
          // Handle duration - prioritize widget duration, then prescription duration
          String prescriptionDuration = medicine['duration'] ?? '';
          _durationController.text = widget.duration.isNotEmpty ? widget.duration : prescriptionDuration;

          // Initialize times from prescription or use defaults
          if (medicine['time'] != null) {
            _selectedTimes = _parseTimesFromString(medicine['time']);
          } else {
            _selectedTimes = _defaultTimes[_selectedTiming] ?? [TimeOfDay(hour: 8, minute: 0)];
          }
        });
        
        print('📋 Initialized from prescription:');
        print('  - Name: ${_medicineNameController.text}');
        print('  - Type: $_selectedType');
        print('  - Timing: $_selectedTiming');
        print('  - Frequency: $_selectedFrequency');
        print('  - Food Instructions: $_selectedFoodTiming');
        print('  - Duration: ${_durationController.text}');
        print('  - Times: ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
      }
    } else if (widget.medicineId != null && _isEditMode) {
      // Only load existing data if we're in edit mode and have a medicine ID
      _loadExistingMedicineData();
    }
  }

  Future<void> _loadExistingMedicineData() async {
    if (widget.medicineId == null) return;
    
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final medicineService = MedicineService();
      
      if (authService.userDetails != null) {
        // Use local-first approach for faster loading
        final medicineData = await medicineService.getMedicineLocalFirst(
          authService.userDetails!.id, 
          widget.medicineId!
        );
        
        if (medicineData != null) {
          print('📋 Loaded medicine data: ${medicineData['name']}');
          print('🔍 Medicine time data: "${medicineData['time']}"');
          
          // Simplified image path handling - just use the stored paths directly
          String? frontImagePath = medicineData['frontImagePath'];
          String? backImagePath = medicineData['backImagePath'];
          
          print('🖼️ Front image path: $frontImagePath');
          print('🖼️ Back image path: $backImagePath');
          
          // Load voice file path if available
          String? voiceFilePath = medicineData['voiceFilePath'];
          print('🎤 Voice file path: ${voiceFilePath ?? 'null'}');
          
          // Simple file loading - just check if files exist
          File? frontImageFile;
          File? backImageFile;
          
          if (frontImagePath != null && frontImagePath.isNotEmpty) {
            final frontFile = File(frontImagePath);
            if (await frontFile.exists()) {
              frontImageFile = frontFile;
              print('✅ Front image loaded: ${frontFile.path}');
            }
          }
          
          if (backImagePath != null && backImagePath.isNotEmpty) {
            final backFile = File(backImagePath);
            if (await backFile.exists()) {
              backImageFile = backFile;
              print('✅ Back image loaded: ${backFile.path}');
            }
          }
          
          setState(() {
            // Update all form fields from database data
            _medicineNameController.text = medicineData['name'] ?? '';
            _dosageController.text = medicineData['dosage'] ?? '';
            _instructionsController.text = medicineData['instructions'] ?? '';
            
            // Update dropdown selections
            _selectedType = _formatMedicineType(medicineData['type'] ?? 'Tablet');
            _selectedFrequency = medicineData['frequency'] ?? 'Once Daily';
            _selectedTiming = medicineData['timing'] ?? 'Morning';
            _selectedFoodTiming = (medicineData['foodInstructions'] as String?)?.isNotEmpty == true ? medicineData['foodInstructions'] : 'Anytime';
            
            // Update validation status
            _isValidated = medicineData['isValidated'] ?? false;
            
            // Always use database duration for editing, override widget duration
            final databaseDuration = medicineData['duration'] ?? '';
            _durationController.text = databaseDuration;
            
            // Set the image files
            _frontImage = frontImageFile;
            _backImage = backImageFile;
            
            // Load voice file path if available
            _voiceFilePath = medicineData['voiceFilePath'];
            if (_voiceFilePath != null) {
              print('🎤 Loaded voice file path: $_voiceFilePath');
            }
            
            // Handle time data with better error handling
            String? timeData = medicineData['time']?.toString();
            
            // Check multiple possible time fields
            if (timeData == null || timeData.isEmpty) {
              timeData = medicineData['mappedTime']?.toString();
            }
            if (timeData == null || timeData.isEmpty) {
              timeData = medicineData['reminderTime']?.toString();
            }
            
            if (timeData != null && timeData.isNotEmpty) {
              print('🔍 Parsing time data: "$timeData"');
              _selectedTimes = _parseTimesFromString(timeData);
              print('✅ Parsed ${_selectedTimes.length} times: ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
              
              // Don't sync frequency when loading existing data - preserve the saved frequency
              print('🔒 Preserving saved frequency: $_selectedFrequency');
            } else {
              print('⚠️ No time data found in any field, using default times for timing: $_selectedTiming');
              _selectedTimes = _getTimesFromTiming(_selectedTiming);
              print('✅ Set default times: ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
              
              // Only sync frequency if we don't have a specific frequency from database
              if (_selectedFrequency.isEmpty || _selectedFrequency == 'Once Daily') {
                _syncFrequencyWithTimes();
              } else {
                print('🔒 Preserving saved frequency: $_selectedFrequency');
              }
            }
          });
          
          print('📋 Loaded existing medicine data:');
          print('  - Name: ${_medicineNameController.text}');
          print('  - Dosage: ${_dosageController.text}');
          print('  - Type: $_selectedType');
          print('  - Frequency: $_selectedFrequency');
          print('  - Timing: $_selectedTiming');
          print('  - Food Instructions: $_selectedFoodTiming');
          print('  - Instructions: ${_instructionsController.text}');
          print('  - Duration: ${_durationController.text}');
          print('  - Validated: $_isValidated');
          print('  - Times: ${_selectedTimes.map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}').join(', ')}');
          print('  - Front Image: ${_frontImage?.path ?? 'null'}');
          print('  - Back Image: ${_backImage?.path ?? 'null'}');
          print('  - Voice File: ${_voiceFilePath ?? 'null'}');
          
          // Duration will be set by the playback listeners when needed
        } else {
          print('⚠️ No medicine data found for ID: ${widget.medicineId}');
        }
      }
    } catch (e) {
      print('❌ Error loading medicine data: $e');
    }
  }


  List<TimeOfDay> _parseTimesFromString(String timeString) {
    List<TimeOfDay> times = [];
    print('🔍 Parsing time string: "$timeString"');
    
    // Handle different time formats
    List<String> timeStrings = timeString.split(', ');
    
    for (String timeStr in timeStrings) {
      try {
        timeStr = timeStr.trim();
        print('🔍 Processing time: "$timeStr"');
        
        // Format 1: "08:00 AM" or "8:00 AM"
        if (timeStr.contains('AM') || timeStr.contains('PM')) {
          final parts = timeStr.split(' ');
          if (parts.length == 2) {
            final timeParts = parts[0].split(':');
            int hour = int.parse(timeParts[0]);
            int minute = int.parse(timeParts[1]);
            
            if (parts[1].toUpperCase() == 'PM' && hour != 12) {
              hour += 12;
            } else if (parts[1].toUpperCase() == 'AM' && hour == 12) {
              hour = 0;
            }
            
            times.add(TimeOfDay(hour: hour, minute: minute));
            print('✅ Parsed time: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
          }
        }
        // Format 2: "08:00" or "8:00" (24-hour format)
        else if (timeStr.contains(':')) {
          final timeParts = timeStr.split(':');
          int hour = int.parse(timeParts[0]);
          int minute = int.parse(timeParts[1]);
          
                      times.add(TimeOfDay(hour: hour, minute: minute));
            print('✅ Parsed time: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}');
        }
        // Format 3: Single number like "8" (assume minutes = 0)
        else {
          int hour = int.parse(timeStr);
          times.add(TimeOfDay(hour: hour, minute: 0));
          print('✅ Parsed time: ${hour.toString().padLeft(2, '0')}:00');
        }
      } catch (e) {
        print('❌ Error parsing time: "$timeStr" - $e');
      }
    }
    
    if (times.isEmpty) {
      print('⚠️ No times parsed, using default: 08:00');
      return [TimeOfDay(hour: 8, minute: 0)];
    }
    
    print('✅ Successfully parsed ${times.length} times');
    return times;
  }

  List<TimeOfDay> _getTimesFromTiming(String timing) {
    return _defaultTimes[timing] ?? [TimeOfDay(hour: 8, minute: 0)];
  }

  /// Generate times for a specific interval pattern
  List<TimeOfDay> _generateIntervalTimes(int intervalHours, {TimeOfDay? startTime}) {
    final times = <TimeOfDay>[];
    final start = startTime ?? TimeOfDay(hour: 6, minute: 0); // Default start at 6 AM
    
    for (int i = 0; i < 24 ~/ intervalHours; i++) {
      final hour = (start.hour + (i * intervalHours)) % 24;
      times.add(TimeOfDay(hour: hour, minute: start.minute));
    }
    
    return times;
  }

  // Use centralized mapping methods from TimingUtils

  String _mapFoodInstructionsFromPrescription(String instructions) {
    final lowerInstructions = instructions.toLowerCase();
    if (lowerInstructions.contains('before')) return 'Before Food';
    if (lowerInstructions.contains('after')) return 'After Food';
    if (lowerInstructions.contains('with')) return 'With Food';
    if (lowerInstructions.contains('empty')) return 'Empty Stomach';
    return 'Anytime';
  }
  
  // Update medicine voice file path in database
  Future<void> _updateMedicineVoiceFilePath(String medicineId, String voiceFilePath) async {
    try {
      final medicineService = MedicineService();
      final currentUser = Provider.of<AuthService>(context, listen: false).userDetails!;
      
      // Get current medicine data
      final currentData = await medicineService.getMedicineLocalFirst(currentUser.id, medicineId);
      if (currentData != null) {
        // Update with new voice file path
        final updatedData = {
          ...currentData,
          'voiceFilePath': voiceFilePath,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Save updated data
        await medicineService.updateMedicineLocalFirst(currentUser.id, medicineId, updatedData);
        print('✅ Updated voice file path in database: $voiceFilePath');
      }
    } catch (e) {
      print('⚠️ Failed to update voice file path in database: $e');
    }
  }

  // Update medicine voice file path in local storage
  Future<void> _updateLocalStorageVoiceFilePath(String medicineId, String voiceFilePath) async {
    try {
      final medicineService = MedicineService();
      final currentUser = Provider.of<AuthService>(context, listen: false).userDetails!;
      
      // Get current medicine data from local storage
      final currentData = await medicineService.getMedicineLocalFirst(currentUser.id, medicineId);
      if (currentData != null) {
        // Update with new voice file path
        final updatedData = {
          ...currentData,
          'voiceFilePath': voiceFilePath,
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        // Save to local storage immediately
        await medicineService.saveMedicineToLocalStorage(currentUser.id, medicineId, updatedData);
        print('✅ Updated voice file path in local storage: $voiceFilePath');
      }
    } catch (e) {
      print('⚠️ Failed to update voice file path in local storage: $e');
    }
  }

  // Update voice file path for new medicine after ID is generated
  Future<void> _updateVoiceFilePathForNewMedicine(String newMedicineId) async {
    try {
      if (_voiceFilePath == null) {
        return;
      }
      
      print('🔄 Updating voice file path for new medicine ID: $newMedicineId');
      
      // Get the directory for voice recordings
      Directory voiceDir;
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          voiceDir = Directory('${externalDir.path}/voice_recordings');
        } else {
          final directory = await getApplicationDocumentsDirectory();
          voiceDir = Directory('${directory.path}/voice_recordings');
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        voiceDir = Directory('${directory.path}/voice_recordings');
      }
      
      // Create new filename with the actual medicine ID
      final newFileName = 'voice_$newMedicineId.m4a';
      final newVoiceFilePath = '${voiceDir.path}/$newFileName';
      
      // Rename the file to use the medicine ID
      final oldFile = File(_voiceFilePath!);
      if (await oldFile.exists()) {
        await oldFile.rename(newVoiceFilePath);
        
        // Update the voice file path
        _voiceFilePath = newVoiceFilePath;
        
        print('✅ Renamed voice file: ${oldFile.path} -> $newVoiceFilePath');
        
        // Update the database with the new voice file path
        await _updateMedicineVoiceFilePath(newMedicineId, newVoiceFilePath);
        
        // Also update local storage with the new voice file path
        await _updateLocalStorageVoiceFilePath(newMedicineId, newVoiceFilePath);
      }
    } catch (e) {
      print('⚠️ Failed to update voice file path for new medicine: $e');
    }
  }

  // Clean up old voice files for a specific medicine
  Future<void> _cleanupOldVoiceFiles(Directory voiceDir, String? medicineId) async {
    try {
      if (medicineId == null) return;
      
      final files = voiceDir.listSync();
      int deletedCount = 0;
      
      for (final file in files) {
        if (file is File) {
          final fileName = file.path.split('/').last;
          // Delete old voice files for this medicine (any format)
          if (fileName.startsWith('voice_$medicineId') && 
              (fileName.endsWith('.m4a') || fileName.endsWith('.mp3') || fileName.endsWith('.aac'))) {
            try {
              await file.delete();
              deletedCount++;
              print('🗑️ Deleted old voice file: $fileName');
            } catch (e) {
              print('⚠️ Could not delete old voice file: $fileName - $e');
            }
          }
        }
      }
      
      if (deletedCount > 0) {
        print('🧹 Cleaned up $deletedCount old voice files for medicine: $medicineId');
      }
    } catch (e) {
      print('⚠️ Error cleaning up old voice files: $e');
    }
  }
  
  @override
  void dispose() {
    _medicineNameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _durationController.dispose();
    _animationController.dispose();
    
    // Clean up audio resources
    _stopPlaybackMonitor();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    
    super.dispose();
  }

  Future<void> _deleteImage(bool isFront) async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete Image'),
            ],
          ),
          content: Text('Are you sure you want to delete this image? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        if (isFront) {
          _frontImage = null;
        } else {
          _backImage = null;
        }
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Image deleted successfully!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<File> _optimizeImage(File imageFile) async {
    try {
      // Check file size
      final int fileSize = await imageFile.length();
      final int maxSize = 1024 * 1024; // 1MB
      
      if (fileSize <= maxSize) {
        // File is already small enough, return as is
        return imageFile;
      }
      
      // For now, return the original file
      // In a production app, you might want to add image compression here
      // using packages like flutter_image_compress
      print('📊 Image size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)}MB');
      return imageFile;
    } catch (e) {
      print('❌ Error optimizing image: $e');
      return imageFile; // Return original file if optimization fails
    }
  }

  Future<bool> _requestCameraPermission() async {
    PermissionStatus status = await Permission.camera.status;
    
    // If already granted, return true immediately
    if (status.isGranted) {
      return true;
    }
    
    // If denied, request permission
    if (status.isDenied) {
      status = await Permission.camera.request();
      return status.isGranted;
    }
    
    // If permanently denied, show settings dialog only once per session
    if (status.isPermanentlyDenied) {
      // Check if we've already shown the dialog in this session
      if (!_hasShownPermissionDialog) {
        _hasShownPermissionDialog = true;
        
        // Show dialog to open app settings
        final bool? shouldOpenSettings = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.camera_alt, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Camera Permission Required'),
                ],
              ),
              content: Text(
                'Camera access is required to take photos. Please enable camera permission in app settings.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('Open Settings'),
                ),
              ],
            );
          },
        );
        
        if (shouldOpenSettings == true) {
          await openAppSettings();
        }
      }
      return false;
    }
    
    return false;
  }

  Future<void> _pickImage(bool isFront) async {
    // Show dialog to choose between camera and gallery
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.photo_camera, color: Theme.of(context).primaryColor),
              SizedBox(width: 8),
              Text('Choose Image Source'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: Colors.blue),
                title: Text('Take Photo'),
                subtitle: Text('Use camera to capture image'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: Colors.green),
                title: Text('Choose from Gallery'),
                subtitle: Text('Select from your photo library'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
          ],
        );
      },
    );

    if (source == null) return;

    // Check camera permission if camera is selected
    if (source == ImageSource.camera) {
      final bool hasPermission = await _requestCameraPermission();
      if (!hasPermission) {
        return; // Silently return if permission denied or cancelled
      }
    }

    setState(() {
      _isProcessingImage = true;
    });

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 512,
        maxHeight: 512,
      );
      
      if (image != null) {
        // Optimize the image if it's too large
        File optimizedImage = await _optimizeImage(File(image.path));
        
        setState(() {
          if (isFront) {
            _frontImage = optimizedImage;
          } else {
            _backImage = optimizedImage;
          }
          _isProcessingImage = false;
        });
        
        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text('Image ${source == ImageSource.camera ? 'captured' : 'selected'} successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _isProcessingImage = false;
        });
      }
    } catch (e) {
      print('❌ Error picking image: $e');
      setState(() {
        _isProcessingImage = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Failed to ${source == ImageSource.camera ? 'capture' : 'select'} image: $e'),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _validateMedicine() async {
    setState(() {
      _isValidated = true;
    });
    
    await Future.delayed(Duration(seconds: 1));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 8),
            Text('Medicine validated successfully!'),
          ],
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  // Generate a hash for the image name to avoid name collisions
  String _generateImageHash(File imageFile, String prefix) {
    final bytes = utf8.encode(imageFile.path + DateTime.now().toString());
    final digest = sha256.convert(bytes);
    return '$prefix${digest.toString().substring(0, 10)}';
  }

  // Save image to local application directory
  Future<String?> _saveImageLocally(File? imageFile, String medicineId, bool isFront) async {
    if (imageFile == null) return null;
    
    try {
      // Validate the source image file
      if (!await imageFile.exists()) {
        print('❌ Source image file does not exist: ${imageFile.path}');
        return null;
      }
      
      final sourceFileSize = await imageFile.length();
      if (sourceFileSize <= 0) {
        print('❌ Source image file has zero size: ${imageFile.path}');
        return null;
      }
      
      print('📸 Saving image: ${imageFile.path} (size: $sourceFileSize bytes)');
      
      final appDir = await getApplicationDocumentsDirectory();
      final medicineImagesDir = Directory('${appDir.path}/medicine_images');
      
      // Create directory if it doesn't exist
      if (!await medicineImagesDir.exists()) {
        await medicineImagesDir.create(recursive: true);
        print('📁 Created medicine_images directory: ${medicineImagesDir.path}');
      }
      
      // Generate unique filename
      final prefix = isFront ? 'front_' : 'back_';
      final extension = path.extension(imageFile.path);
      final fileName = _generateImageHash(imageFile, prefix) + extension;
      
      // Save the image
      final savedImagePath = '${medicineImagesDir.path}/$fileName';
      
      // Copy the file with error handling
      try {
        await imageFile.copy(savedImagePath);
        print('📋 Image copied to: $savedImagePath');
      } catch (copyError) {
        print('❌ Error copying image: $copyError');
        return null;
      }
      
      // Validate the saved file
      final savedFile = File(savedImagePath);
      if (!await savedFile.exists()) {
        print('❌ Saved image file does not exist after copy: $savedImagePath');
        return null;
      }
      
      final savedFileSize = await savedFile.length();
      if (savedFileSize <= 0) {
        print('❌ Saved image file has zero size: $savedImagePath');
        // Try to delete the empty file
        try {
          await savedFile.delete();
        } catch (e) {
          print('⚠️ Could not delete empty file: $e');
        }
        return null;
      }
      
      // Ensure file permissions are set correctly for native code access
      try {
        await savedFile.setLastModified(DateTime.now());
        print('✅ Image saved successfully at: $savedImagePath (size: $savedFileSize bytes)');
        
        // Verify the file can be read
        final testRead = await savedFile.readAsBytes();
        if (testRead.isEmpty) {
          print('❌ Saved image file cannot be read: $savedImagePath');
          return null;
        }
        
        return savedImagePath;
      } catch (e) {
        print('⚠️ Warning when setting file metadata: $e');
        // Still return the path if the file exists and has content
        if (await savedFile.exists() && await savedFile.length() > 0) {
          return savedImagePath;
        }
        return null;
      }
    } catch (e) {
      print('❌ Error saving image locally: $e');
      return null;
    }
  }

  Future<void> _saveMedicine() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedTimes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please add at least one time'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.userDetails!;

      // Convert times to 12-hour format for consistency
      String timeString = _selectedTimes.map((time) {
        final hour = time.hour;
        final minute = time.minute;
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
      }).join(', ');

      final medicineService = MedicineService();
      
      // Simplified image saving - just save new images and preserve existing ones
      String? frontImagePath;
      String? backImagePath;
      
      // Save new images if provided
      if (_frontImage != null) {
        frontImagePath = await _saveImageLocally(_frontImage, 
            widget.medicineId ?? DateTime.now().millisecondsSinceEpoch.toString(), true);
        print('📸 Front image saved: $frontImagePath');
      }
      
      if (_backImage != null) {
        backImagePath = await _saveImageLocally(_backImage, 
            widget.medicineId ?? DateTime.now().millisecondsSinceEpoch.toString(), false);
        print('📸 Back image saved: $backImagePath');
      }
      
      // For editing mode, preserve existing image paths if no new images were saved
      if (widget.medicineId != null && _isEditMode) {
        try {
          final existingData = await medicineService.getMedicineLocalFirst(
            currentUser.id, 
            widget.medicineId!
          );
          
          if (frontImagePath == null) {
            frontImagePath = existingData?['frontImagePath'];
          }
          
          if (backImagePath == null) {
            backImagePath = existingData?['backImagePath'];
          }
        } catch (e) {
          print('⚠️ Could not retrieve existing image paths: $e');
        }
      }
      
      // Prepare base medicine data
      final baseMedicineData = {
        'name': _medicineNameController.text.trim(),
        'dosage': _dosageController.text.trim(),
        'type': _selectedType,
        'frequency': _selectedFrequency,
        'timing': _selectedTiming,
        'foodInstructions': _selectedFoodTiming,
        'time': timeString,
        'instructions': _instructionsController.text.trim(),
        'isValidated': _isValidated,
        'duration': _durationController.text.trim(),
        'mappedTiming': _selectedTiming,
        'mappedFrequency': _selectedFrequency,
        'mappedFoodInstructions': _selectedFoodTiming,
        'mappedTime': timeString,
        'isActive': true,
        'lastUpdated': DateTime.now().toIso8601String(),
        'createdAt': _isEditMode ? null : DateTime.now().toIso8601String(),
        'frontImagePath': frontImagePath,
        'backImagePath': backImagePath,
        'voiceFilePath': _voiceFilePath, // Voice file path
        'isFromPrescription': widget.isFromPrescription,
        'prescriptionData': widget.prescriptionData,
      };
      
      print('🔍 Saving medicine with duration: "${_durationController.text.trim()}"');
      print('🔍 Base medicine data duration: "${baseMedicineData['duration']}"');
      
      if (_isEditMode && widget.medicineId != null) {
        // OPTIMIZED HYBRID APPROACH: Local-first with smart database sync
        print('🔄 Using optimized hybrid approach for medicine update: ${widget.medicineId}');
        
        // Add calendar selection info to the medicine data if using date range
        if (_useDateRange && _startDate != null && _endDate != null) {
          baseMedicineData['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
          baseMedicineData['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
          baseMedicineData['isCalendarSelection'] = true;
        }
        
        // Step 1: Update local storage immediately for instant UI response
        // Ensure the medicine data includes the existing ID to prevent duplicates
        final updatedMedicineData = {
          ...baseMedicineData,
          'id': widget.medicineId!, // Preserve existing ID
          'lastUpdated': DateTime.now().toIso8601String(),
        };
        
        await medicineService.updateMedicineLocalFirst(
          currentUser.id,
          widget.medicineId!,
          updatedMedicineData,
        );
        
        // Step 2: Smart database sync in background (non-blocking)
        _optimizedDatabaseSyncInBackground(
          medicineService,
          currentUser.id,
          widget.medicineId!,
          updatedMedicineData,
        );
        
      } else {
        // OPTIMIZED HYBRID APPROACH: New medicine creation with smart database sync
        print('🆕 Using optimized hybrid approach for new medicine creation');
        
        // Parse duration to determine how to save the medicine
        final durationText = _durationController.text.trim();
        final durationDays = DurationHelper.parseDurationToDays(durationText);
        
        // Step 1: Create medicine with local-first approach for instant UI
        final newMedicineId = await _createMedicineWithLocalFirst(
          medicineService,
          currentUser.id,
          baseMedicineData,
          durationDays,
        );
        
        // Step 1.5: Update voice file path for new medicine
        if (_voiceFilePath != null) {
          await _updateVoiceFilePathForNewMedicine(newMedicineId);
          
          // Update the baseMedicineData with the new voice file path
          baseMedicineData['voiceFilePath'] = _voiceFilePath;
        }
        
        // Step 2: Smart database sync in background with updated data
        _syncNewMedicineToDatabase(
          medicineService,
          currentUser.id,
          newMedicineId,
          baseMedicineData, // This now contains the updated voice file path
          durationDays,
        );
      }

      setState(() {
        _isSaving = false;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditMode ? 'Medicine updated successfully!' : 'Medicine added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Navigate back
      Navigator.of(context).pop(true);

    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      
      print('Error saving medicine: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving medicine: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Non-blocking database sync in background
  void _optimizedDatabaseSyncInBackground(
    MedicineService medicineService,
    String userId,
    String medicineId,
    Map<String, dynamic> medicineData,
  ) {
    // Run in background without blocking UI
    Future.microtask(() async {
      try {
        print('🔄 Starting background database sync for medicine: $medicineId');
        
        // Step 1: Check if we need to update schedule (only if duration/calendar changed)
        final needsScheduleUpdate = _useDateRange && _startDate != null && _endDate != null;
        
        if (needsScheduleUpdate) {
          // Parse duration for schedule update
          final durationText = _durationController.text.trim();
          final durationDays = DurationHelper.parseDurationToDays(durationText);
          
          // Step 2: Smart schedule update - only update if necessary
          await _smartScheduleUpdate(
            medicineService,
            userId,
            medicineId,
            medicineData,
            durationDays,
          );
        } else {
          // Step 3: Simple database update without schedule changes
          await medicineService.updateMedicineDocumentBased(
            userId,
            medicineId,
            medicineData,
          );
          print('✅ Simple database update completed in background');
        }
        
        print('✅ Background database sync completed');
        
      } catch (e) {
        print('⚠️ Background database sync failed, but local update succeeded: $e');
        // Don't throw error - local update already succeeded
        // Schedule retry in background
        _scheduleRetry(userId, medicineId, medicineData);
      }
    });
  }

  // Smart schedule update that minimizes database operations
  Future<void> _smartScheduleUpdate(
    MedicineService medicineService,
    String userId,
    String medicineId,
    Map<String, dynamic> medicineData,
    int? durationDays,
  ) async {
    try {
      print('🧠 Smart schedule update for medicine: $medicineId');
      
      // Step 1: Check if schedule actually needs updating
      final existingData = await medicineService.getMedicineLocalFirst(userId, medicineId);
      final existingStartDate = existingData?['calendarStartDate'];
      final existingEndDate = existingData?['calendarEndDate'];
      final existingDuration = existingData?['duration'];
      
      final newStartDate = _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : null;
      final newEndDate = _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : null;
      final newDuration = _durationController.text.trim();
      
      // Check if schedule actually changed
      final scheduleChanged = existingStartDate != newStartDate ||
                             existingEndDate != newEndDate ||
                             existingDuration != newDuration;
      
      if (!scheduleChanged) {
        print('✅ Schedule unchanged, skipping schedule update');
        // Just update the main medicine data
        await medicineService.updateMedicineDocumentBased(
          userId,
          medicineId,
          medicineData,
        );
        return;
      }
      
      print('🔄 Schedule changed, performing optimized update');
      
      // Step 2: Batch update - update main medicine and schedule together
      if (durationDays != null && durationDays > 1) {
        // Duration-based medicine: Update schedule efficiently
        await _batchUpdateWithSchedule(
          medicineService,
          userId,
          medicineId,
          medicineData,
          durationDays,
        );
      } else {
        // Single medicine: Simple update
        await medicineService.updateMedicineDocumentBased(
          userId,
          medicineId,
          medicineData,
        );
      }
      
      print('✅ Smart schedule update completed');
      
    } catch (e) {
      print('❌ Smart schedule update failed: $e');
      // Fallback to simple update
      await medicineService.updateMedicineDocumentBased(
        userId,
        medicineId,
        medicineData,
      );
    }
  }

  // Batch update that combines medicine and schedule updates
  Future<void> _batchUpdateWithSchedule(
    MedicineService medicineService,
    String userId,
    String medicineId,
    Map<String, dynamic> medicineData,
    int durationDays,
  ) async {
    try {
      print('📦 Batch updating medicine and schedule');
      
      // Create schedule entries efficiently
      final List<Map<String, dynamic>> scheduleEntries = [];
      final startDate = _startDate ?? DateTime.now();
      
      for (int i = 0; i < durationDays; i++) {
        final scheduleDate = startDate.add(Duration(days: i));
        final dateString = DateFormat('yyyy-MM-dd').format(scheduleDate);
        
        scheduleEntries.add({
          'date': dateString,
          'time': medicineData['time'],
          'isCompleted': false,
          'completedAt': null,
        });
      }
      
      // Add schedule data to medicine data
      final updatedMedicineData = {
        ...medicineData,
        'scheduleDates': scheduleEntries.map((e) => e['date']).toList(),
        'scheduleData': scheduleEntries,
        'totalDays': durationDays,
        'startDate': DateFormat('yyyy-MM-dd').format(startDate),
        'endDate': DateFormat('yyyy-MM-dd').format(startDate.add(Duration(days: durationDays - 1))),
      };
      
      // Single database operation for both medicine and schedule
      await medicineService.updateMedicineDocumentBased(
        userId,
        medicineId,
        updatedMedicineData,
      );
      
      print('✅ Batch update completed');
      
    } catch (e) {
      print('❌ Batch update failed: $e');
      throw e;
    }
  }

  // Schedule retry for failed database operations
  void _scheduleRetry(String userId, String medicineId, Map<String, dynamic> medicineData) {
    // Schedule retry after 5 seconds
    Future.delayed(Duration(seconds: 5), () async {
      try {
        print('🔄 Retrying database sync for medicine: $medicineId');
        final medicineService = MedicineService();
        await medicineService.updateMedicineDocumentBased(
          userId,
          medicineId,
          medicineData,
        );
        print('✅ Retry successful');
      } catch (e) {
        print('❌ Retry failed: $e');
        // Could implement exponential backoff here
      }
    });
  }

  // Background method to update schedule for calendar integration without blocking UI
  void _updateScheduleInBackground(
    MedicineService medicineService,
    String userId,
    String medicineId,
    Map<String, dynamic> medicineData,
    int? durationDays,
  ) {
    // Run in background without awaiting
    Future.microtask(() async {
      try {
        print('🔄 Updating schedule in background for calendar integration...');
        
        if (durationDays != null && durationDays > 1) {
          // Duration-based medicine: Create entries for each date
          final List<Map<String, dynamic>> medicineEntries = [];
          
          // Use calendar selection dates if available, otherwise use today
          DateTime startDate;
          if (_useDateRange && _startDate != null) {
            startDate = _startDate!;
          } else {
            startDate = DateTime.now();
          }
          
          for (int i = 0; i < durationDays; i++) {
            final scheduleDate = startDate.add(Duration(days: i));
            final dateString = DateFormat('yyyy-MM-dd').format(scheduleDate);
            
            final entryData = {
              ...medicineData,
              'scheduleDate': dateString,
              'isCompleted': false,
              'completedAt': null,
            };
            
            // Add calendar selection info if using date range
            if (_useDateRange && _startDate != null && _endDate != null) {
              entryData['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
              entryData['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
              entryData['isCalendarSelection'] = true;
            }
            
            medicineEntries.add(entryData);
          }
          
          // Save new schedule entries in background
          await medicineService.saveMedicinesDocumentBased(
            userId,
            medicineEntries,
            {'id': 'manual_updated', 'source': 'manual'},
          );
        } else {
          // Single medicine: Create entry for today or selected start date
          String scheduleDate;
          if (_useDateRange && _startDate != null) {
            scheduleDate = DateFormat('yyyy-MM-dd').format(_startDate!);
          } else {
            scheduleDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          }
          
          final medicineEntry = {
            ...medicineData,
            'scheduleDate': scheduleDate,
            'isCompleted': false,
            'completedAt': null,
          };
          
          // Add calendar selection info if using date range
          if (_useDateRange && _startDate != null && _endDate != null) {
            medicineEntry['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
            medicineEntry['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
            medicineEntry['isCalendarSelection'] = true;
          }
          
          // Save new schedule entry in background
          await medicineService.saveMedicinesDocumentBased(
            userId,
            [medicineEntry],
            {'id': 'manual_updated', 'source': 'manual'},
          );
        }
        
        print('✅ Background schedule update completed');
      } catch (e) {
        print('⚠️ Background schedule update failed: $e');
        // Don't throw error since this is background operation
      }
    });
  }

  // Note: Old methods removed - now using document-based approach via MedicineService

  // Voice recording methods
  Future<void> _startRecording() async {
    try {
      // Check microphone permission
      if (!await _audioRecorder.hasPermission()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Microphone permission is required for voice recording'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      print('🎤 Microphone permission granted');

      // Get the directory for storing recordings - use external storage for Android service access
      Directory voiceDir;
      if (Platform.isAndroid) {
        // Use external storage for Android service access
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          voiceDir = Directory('${externalDir.path}/voice_recordings');
        } else {
          // Fallback to app documents directory
          final directory = await getApplicationDocumentsDirectory();
          voiceDir = Directory('${directory.path}/voice_recordings');
        }
      } else {
        // Use app documents directory for iOS
        final directory = await getApplicationDocumentsDirectory();
        voiceDir = Directory('${directory.path}/voice_recordings');
      }
      
      if (!await voiceDir.exists()) {
        await voiceDir.create(recursive: true);
      }
      
      // Clean up old voice files for this medicine to prevent accumulation
      await _cleanupOldVoiceFiles(voiceDir, widget.medicineId);

      // Generate filename using medicine ID
      // Use M4A format with AAC encoder for best compatibility
      final medicineId = widget.medicineId;
      if (medicineId == null) {
        // For new medicines, we'll update the file path after the medicine is created
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        final fileName = 'voice_$tempId.m4a';
        _voiceFilePath = '${voiceDir.path}/$fileName';
      } else {
        // For existing medicines, use the actual medicine ID
        final fileName = 'voice_$medicineId.m4a';
        _voiceFilePath = '${voiceDir.path}/$fileName';
      }
      
      print('🎤 Voice file path set to: $_voiceFilePath');

      print('🎤 Starting recording to: $_voiceFilePath');
      print('📁 Directory exists: ${await voiceDir.exists()}');

      // Start recording with AAC encoder (best compatibility with MediaPlayer)
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _voiceFilePath!
      );
      
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });
      
      // Haptic feedback for recording start
      HapticFeedback.lightImpact();

      // Start recording duration timer
      _startRecordingTimer();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recording started'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      
      // Keep the original path we set during startRecording
      // The path from stop() might be different or null
      final savedPath = _voiceFilePath ?? path;
      
      setState(() {
        _isRecording = false;
        _voiceFilePath = savedPath;
      });
      
      // Haptic feedback for recording stop
      HapticFeedback.mediumImpact();

      // Verify the file was actually created and validate it
      if (_voiceFilePath != null) {
        final file = File(_voiceFilePath!);
        
        // Wait a bit for file system to catch up
        await Future.delayed(Duration(milliseconds: 500));
        
        if (await file.exists()) {
          final fileSize = await file.length();
          print('✅ Voice recording saved successfully: $_voiceFilePath');
          print('📁 File size: ${fileSize} bytes');
          
          // Validate file is not empty
          if (fileSize > 0) {
            // Ensure file has correct M4A extension for AAC encoder
            if (!_voiceFilePath!.toLowerCase().endsWith('.m4a')) {
              try {
                final newPath = _voiceFilePath!.substring(0, _voiceFilePath!.lastIndexOf('.')) + '.m4a';
                final renamed = await file.rename(newPath);
                setState(() {
                  _voiceFilePath = renamed.path;
                });
                print('🔄 Renamed voice file to M4A: $_voiceFilePath');
              } catch (e) {
                print('⚠️ Failed to rename voice file to .m4a: $e');
              }
            }
            // Duration will be set by the playback listeners when needed
            // Update the medicine data with the new voice file path
            if (widget.medicineId != null) {
              await _updateMedicineVoiceFilePath(widget.medicineId!, _voiceFilePath!);
            }
          } else {
            print('❌ Voice recording file is empty, removing it');
            try {
              await file.delete();
              setState(() {
                _voiceFilePath = null;
              });
            } catch (e) {
              print('⚠️ Failed to delete empty voice file: $e');
            }
          }
        } else {
          print('❌ Voice recording file not found: $_voiceFilePath');
          setState(() {
            _voiceFilePath = null;
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_voiceFilePath != null ? 'Recording saved successfully' : 'Failed to save recording'),
          backgroundColor: _voiceFilePath != null ? Colors.green : Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error stopping recording: $e');
      setState(() {
        _isRecording = false;
        _voiceFilePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to stop recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _playRecording() async {
    if (_voiceFilePath == null) return;

    try {
      // Verify file exists before playing
      final file = File(_voiceFilePath!);
      if (!await file.exists()) {
        print('❌ Voice file does not exist: $_voiceFilePath');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice file not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      print('🎵 Playing voice recording: $_voiceFilePath');
      print('📁 File size: ${await file.length()} bytes');

      // Validate file is not empty
      final fileSize = await file.length();
      if (fileSize == 0) {
        print('❌ Voice file is empty, cannot play');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voice recording is empty'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Stop any current playback first
      await _audioPlayer.stop();
      
      // Use low latency mode for MP3 files
      await _audioPlayer.setPlayerMode(PlayerMode.lowLatency);
      await _audioPlayer.setVolume(1.0);
      
      // Configure audio context for proper playback
      await _audioPlayer.setAudioContext(AudioContext(
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.voiceCommunication,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ));
      
      // Add a delay to ensure file is fully written
      await Future.delayed(Duration(milliseconds: 500));
      
      // Play the MP3 file with DeviceFileSource
      try {
        await _audioPlayer.play(DeviceFileSource(_voiceFilePath!));
        print('✅ MP3 voice recording playback started successfully');
      } catch (e) {
        print('❌ DeviceFileSource failed: $e');
        print('🔄 Trying with MediaPlayer mode...');
        
        // Fallback to MediaPlayer mode
        try {
          await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
          await _audioPlayer.play(DeviceFileSource(_voiceFilePath!));
          print('✅ MediaPlayer mode succeeded');
        } catch (e2) {
          print('❌ Both methods failed: $e2');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to play voice recording. Try recording again.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }
      }
      
      setState(() {
        _isPlaying = true;
      });

      // Set up listeners only once
      _setupAudioListeners();
      
      // Add a fallback timer to check if playback is still active
      _startPlaybackMonitor();
      
      // Add a timeout to force stop if playback goes too long
      Timer(Duration(seconds: 30), () {
        if (_isPlaying && mounted) {
          print('🛑 Playback timeout - forcing stop');
          setState(() {
            _isPlaying = false;
            _playbackPosition = Duration.zero;
          });
          _stopPlaybackMonitor();
        }
      });

      // Try to get duration immediately
      try {
        final duration = await _audioPlayer.getDuration();
        if (duration != null && duration.inMilliseconds > 0) {
          print('🎵 Immediate duration: ${duration.inMilliseconds}ms');
          if (mounted) {
            setState(() {
              _playbackDuration = duration;
            });
          }
        } else {
          // Fallback: try again after a short delay
          Future.delayed(Duration(milliseconds: 500), () async {
            try {
              final fallbackDuration = await _audioPlayer.getDuration();
              if (fallbackDuration != null && fallbackDuration.inMilliseconds > 0) {
                print('🎵 Fallback duration: ${fallbackDuration.inMilliseconds}ms');
                if (mounted) {
                  setState(() {
                    _playbackDuration = fallbackDuration;
                  });
                }
              }
            } catch (e) {
              print('🎤 Fallback duration failed: $e');
            }
          });
        }
      } catch (e) {
        print('🎤 _updatePlaybackDuration: Error getting immediate duration: $e');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Playing voice recording...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('Error playing recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play recording. Recording saved but preview unavailable.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _stopPlaybackMonitor();
      setState(() {
        _isPlaying = false;
        _playbackPosition = Duration.zero;
      });
      print('🛑 Playback stopped manually');
    } catch (e) {
      print('Error stopping playback: $e');
    }
  }

  Future<void> _deleteRecording() async {
    try {
      if (_voiceFilePath != null) {
        final file = File(_voiceFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await _audioPlayer.stop();

      setState(() {
        _voiceFilePath = null;
        _isPlaying = false;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _recordingDuration = Duration.zero;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voice recording deleted'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      print('Error deleting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete recording: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updatePlaybackDuration() async {
    if (_voiceFilePath == null) {
      print('🎤 _updatePlaybackDuration: _voiceFilePath is null, returning');
      return;
    }

    print('🎤 _updatePlaybackDuration: Updating duration for $_voiceFilePath');

    try {
      // Try to get duration without setting source (to avoid conflicts)
      Duration? duration = await _audioPlayer.getDuration();
      print('🎤 _updatePlaybackDuration: Got duration: $duration');

      if (duration != null && duration.inMilliseconds > 0) {
        print('🎤 _updatePlaybackDuration: Setting playback duration to $duration');
        if (mounted) {
          setState(() {
            _playbackDuration = duration!;
            if (_playbackPosition > duration!) {
              _playbackPosition = Duration.zero;
            }
          });
        }
      } else {
        print('🎤 _updatePlaybackDuration: No valid duration, using recording duration fallback');
        // As a final fallback, keep showing recording duration if available
        if (_recordingDuration.inMilliseconds > 0 && mounted) {
          setState(() {
            _playbackDuration = _recordingDuration;
          });
        }
      }
    } catch (e) {
      print('🎤 _updatePlaybackDuration: Error getting duration: $e');
      // Use recording duration as fallback
      if (_recordingDuration.inMilliseconds > 0 && mounted) {
        setState(() {
          _playbackDuration = _recordingDuration;
        });
      }
    }
  }

  void _startRecordingTimer() {
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      
      if (mounted) {
        setState(() {
          _recordingDuration = Duration(seconds: _recordingDuration.inSeconds + 1);
        });
      }
    });
  }

  Timer? _playbackMonitorTimer;

  void _setupAudioListeners() {
    // Listen to player state changes
    _audioPlayer.onPlayerStateChanged.listen((state) {
      print('🎵 Player state changed: $state');
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
        
        // Reset position when playback stops or completes
        if (state == PlayerState.stopped || state == PlayerState.completed || state == PlayerState.paused) {
          setState(() {
            _isPlaying = false;
            _playbackPosition = Duration.zero;
          });
          print('🛑 Playback ended automatically');
          _stopPlaybackMonitor();
        }
      }
    });

    // Listen to position changes
    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _playbackPosition = position;
        });
      }
    });

    // Listen to duration changes
    _audioPlayer.onDurationChanged.listen((duration) {
      print('🎵 Duration changed: ${duration.inMilliseconds}ms');
      if (mounted) {
        setState(() {
          _playbackDuration = duration;
        });
      }
    });

    // Listen to player completion
    _audioPlayer.onPlayerComplete.listen((_) {
      print('🎵 Playback completed via onPlayerComplete');
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackPosition = Duration.zero;
        });
        _stopPlaybackMonitor();
      }
    });
  }

  void _startPlaybackMonitor() {
    _stopPlaybackMonitor(); // Stop any existing timer
    _playbackMonitorTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (!_isPlaying || !mounted) {
        timer.cancel();
        return;
      }
      
      // Check if playback has actually ended by checking position vs duration
      if (_playbackDuration.inMilliseconds > 0 && _playbackPosition.inMilliseconds >= _playbackDuration.inMilliseconds - 100) {
        print('🛑 Playback monitor detected end of playback by position');
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _playbackPosition = Duration.zero;
          });
        }
        timer.cancel();
      }
      
      // Also check if position hasn't changed for a while (stuck playback)
      if (_playbackPosition.inMilliseconds > 0 && _playbackDuration.inMilliseconds > 0) {
        final progress = _playbackPosition.inMilliseconds / _playbackDuration.inMilliseconds;
        if (progress >= 0.99) { // 99% complete
          print('🛑 Playback monitor detected near completion');
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _playbackPosition = Duration.zero;
            });
          }
          timer.cancel();
        }
      }
    });
  }

  void _stopPlaybackMonitor() {
    _playbackMonitorTimer?.cancel();
    _playbackMonitorTimer = null;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (widget.isFromPrescription) {
              Navigator.pop(context, {
                'action': 'back',
                'medicineData': {
                  'name': _medicineNameController.text,
                  'dosage': _dosageController.text,
                  'type': _selectedType,
                  'frequency': _selectedFrequency,
                  'timing': _selectedTiming,
                  'foodInstructions': _selectedFoodTiming,
                  'time': _selectedTimes.map((time) => time.format(context)).join(', '),
                  'instructions': _instructionsController.text,
                  'isValidated': _isValidated,
                  'duration': _durationController.text,
                },
                'originalName': widget.medicineName,
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _isEditMode 
            ? 'Edit Medicine Details'
            : widget.isFromPrescription 
              ? _isValidated 
                ? 'Medicine Details'
                : 'Verify Medicine Details'
              : 'Add Medicine Details',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.isFromPrescription && !_isValidated)
            IconButton(
              icon: Icon(Icons.verified_user, color: Theme.of(context).primaryColor),
              onPressed: _validateMedicine,
            ),
          IconButton(
            icon: _isSaving 
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.save, color: Theme.of(context).primaryColor),
            onPressed: _isSaving ? null : _saveMedicine,
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0.0, _slideAnimation.value),
            end: Offset.zero,
          ).animate(_animationController),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isFromPrescription) ...[
                    _buildPrescriptionInfo(),
                    SizedBox(height: 24),
                  ],
                  
                  _buildImageUploadSection(),
                  SizedBox(height: 24),
                  
                  _buildMedicineInfoSection(),
                  SizedBox(height: 24),
                  
                  _buildDosageTimingSection(),
                  SizedBox(height: 24),
                  
                  _buildReminderSection(),
                  SizedBox(height: 24),

                  _buildVoiceRecordingSection(),
                  SizedBox(height: 24),

                  _buildActionButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPrescriptionInfo() {
    if (!widget.isFromPrescription || widget.prescriptionData == null) {
      return SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: Colors.blue.shade600),
              SizedBox(width: 8),
              Text(
                'Prescription Source',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'This medicine was extracted from a scanned prescription.',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          ),
          if (widget.prescriptionData!['diagnosis']?.isNotEmpty == true) ...[
            SizedBox(height: 8),
            _buildInfoRow('Diagnosis:', widget.prescriptionData!['diagnosis']),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageUploadSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.photo_camera,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medicine Images',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Add photos of your medicine for easy identification',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildImageUploadCard(
                  'Front Side',
                  _frontImage,
                  () => _pickImage(true),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildImageUploadCard(
                  'Back Side',
                  _backImage,
                  () => _pickImage(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageUploadCard(String title, File? image, VoidCallback onPick) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: () {
        if (image != null) {
          _showImagePreviewDialog(image, title);
        } else {
          onPick();
        }
      },
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: image != null ? Colors.white : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: image != null ? theme.primaryColor : theme.primaryColor.withOpacity(0.3),
            width: image != null ? 2 : 1.5,
          ),
          boxShadow: image != null ? [
            BoxShadow(
              color: theme.primaryColor.withOpacity(0.2),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ] : [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: image != null
            ? Stack(
                children: [
                  // Image preview
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.file(
                      image,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        print('❌ Error loading image in card: $error');
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image, color: Colors.red, size: 32),
                              SizedBox(height: 4),
                              Text(
                                'Image Error',
                                style: TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Loading overlay when processing
                  if (_isProcessingImage)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Processing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Overlay for tap indication
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withOpacity(0.8),
                            Colors.transparent,
                          ],
                          stops: [0.0, 1.0],
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.touch_app, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Tap to view',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Edit button overlay
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.primaryColor.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.edit, color: Colors.white, size: 16),
                        onPressed: onPick,
                        padding: EdgeInsets.all(4),
                        constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.camera_alt_outlined,
                      size: 28,
                      color: theme.primaryColor,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Camera or Gallery',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _showImagePreviewDialog(File image, String title) {
    try {
      print('📷 Showing image preview: ${image.path}');
      print('📊 File exists: ${image.existsSync()}, size: ${image.lengthSync()} bytes');
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(Icons.photo, color: Theme.of(context).primaryColor),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: BoxConstraints(maxWidth: 350, maxHeight: 350),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    children: [
                      // Show loading indicator while image loads
                      Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      // Image with error handling
                      Image.file(
                        image,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          print('❌ Error loading image: $error');
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image, size: 48, color: Colors.red),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _pickImage(title == 'Front Side');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                            ),
                            icon: Icon(Icons.camera_alt, size: 18),
                            label: Text('Replace'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _deleteImage(title == 'Front Side');
                            },
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              foregroundColor: Colors.red,
                              side: BorderSide(color: Colors.red),
                            ),
                            icon: Icon(Icons.delete, size: 18),
                            label: Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      print('❌ Error showing image preview dialog: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to preview image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMedicineInfoSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _getMedicineTypeIcon(_selectedType),
                color: Theme.of(context).primaryColor,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'Medicine Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              if (widget.isFromPrescription) ...[
                SizedBox(width: 8),
                Icon(Icons.verified, color: Colors.green, size: 20),
              ],
            ],
          ),
          SizedBox(height: 16),
          
          _buildValidatedTextField(
            'Medicine Name',
            _medicineNameController,
            enabled: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter medicine name';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          
          _buildDropdownField(
            'Medicine Type', 
            _selectedType, 
            _medicineTypes,
            enabled: true,
            (value) {
              setState(() {
                _selectedType = value!;
              });
            }
          ),
          SizedBox(height: 16),
          
          _buildValidatedTextField(
            'Dosage',
            _dosageController,
            enabled: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter dosage';
              }
              return null;
            },
          ),
          SizedBox(height: 16),
          _buildDurationField(),
        ],
      ),
    );
  }

  Widget _buildDosageTimingSection() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dosage & Timing',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 16),
          
          TimingUtils.buildFrequencyInput(
            currentFrequency: _selectedFrequency,
            onFrequencyChanged: (value) {
              setState(() {
                _selectedFrequency = value;
              });
              // Update timing and times based on frequency
              _updateTimingFromFrequency(value);
            },
            context: context,
          ),
          SizedBox(height: 16),
          
          _buildTimingField(),
          SizedBox(height: 16),
          
          _buildDropdownField('Food Instructions', _selectedFoodTiming, _foodInstructions, (value) {
            setState(() {
              _selectedFoodTiming = value!;
            });
          }),
          SizedBox(height: 16),

          _buildValidatedTextField(
            'Special Instructions',
            _instructionsController,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildTimingField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timing (When to Take)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _timingOptions.contains(_selectedTiming) ? _selectedTiming : _timingOptions.first,
              isExpanded: true,
              items: _timingOptions.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: _onTimingChanged,
            ),
          ),
        ),
      ],
    );
  }

  void _onTimingChanged(String? value) {
    if (value != null) {
      setState(() {
        _selectedTiming = value;
        if (value == 'Custom') {
          // Keep existing times for custom, but ensure at least one time
          if (_selectedTimes.isEmpty) {
            _selectedTimes = [TimeOfDay(hour: 8, minute: 0)];
          }
        } else if (value.startsWith('Every ') && value.contains(' Hours')) {
          // Handle dynamic interval generation for custom intervals
          final intervalMatch = RegExp(r'Every (\d+) Hours').firstMatch(value);
          if (intervalMatch != null) {
            final intervalHours = int.tryParse(intervalMatch.group(1) ?? '6');
            if (intervalHours != null && intervalHours > 0) {
              _selectedTimes = _generateIntervalTimes(intervalHours);
              print('🔄 Generated interval times for "$value": ${_selectedTimes.map((t) => t.format(context)).join(', ')}');
            } else {
              _selectedTimes = _defaultTimes[value] ?? [TimeOfDay(hour: 8, minute: 0)];
            }
          } else {
            _selectedTimes = _defaultTimes[value] ?? [TimeOfDay(hour: 8, minute: 0)];
          }
        } else {
          // Update times based on selected timing
          _selectedTimes = _defaultTimes[value] ?? [TimeOfDay(hour: 8, minute: 0)];
          print('🔄 Updated times for timing "$value": ${_selectedTimes.map((t) => t.format(context)).join(', ')}');
        }
      });
      
      // Always update frequency from timing to ensure consistency
      _updateFrequencyFromTiming(value);
      print('🔄 Updated frequency to: $_selectedFrequency');
    }
  }

  Widget _buildReminderSection() {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alarm, color: theme.primaryColor, size: 24),
              SizedBox(width: 8),
              Text(
                'Reminder Times',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          Text(
            _selectedTiming == 'Custom' ? 'Custom Times (Tap to edit)' : 'Scheduled Times (Tap to edit)',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._selectedTimes.asMap().entries.map((entry) {
                int index = entry.key;
                TimeOfDay time = entry.value;
                return GestureDetector(
                  onTap: () => _editTime(index),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 16, color: theme.primaryColor),
                        SizedBox(width: 4),
                        Text(
                          time.format(context),
                          style: TextStyle(
                            color: theme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_selectedTiming == 'Custom') ...[
                          SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _removeTime(index),
                            child: Icon(Icons.close, size: 16, color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
              if (_selectedTiming == 'Custom')
                GestureDetector(
                  onTap: _addCustomTime,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16, color: Colors.grey.shade600),
                        SizedBox(width: 4),
                        Text(
                          'Add Time',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTimes[index],
    );
    
    if (picked != null) {
      setState(() {
        _selectedTimes[index] = picked;
        _selectedTimes.sort((a, b) {
          final aMinutes = a.hour * 60 + a.minute;
          final bMinutes = b.hour * 60 + b.minute;
          return aMinutes.compareTo(bMinutes);
        });
      });
      
      // Sync frequency with times after editing
      _syncFrequencyWithTimes();
    }
  }

  void _addCustomTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    
    if (picked != null) {
      setState(() {
        _selectedTimes.add(picked);
        _selectedTimes.sort((a, b) {
          final aMinutes = a.hour * 60 + a.minute;
          final bMinutes = b.hour * 60 + b.minute;
          return aMinutes.compareTo(bMinutes);
        });
      });
      
      // Sync frequency with times after adding
      _syncFrequencyWithTimes();
      
      // Check if timing should be updated based on the new pattern
      _checkAndUpdateTimingFromPattern();
    }
  }

  /// Check if the current times follow a known pattern and update timing accordingly
  void _checkAndUpdateTimingFromPattern() {
    final timeCount = _selectedTimes.length;
    
    // Since we removed "Every X Hours" from timing options, 
    // we'll use "Custom" for any interval patterns
    if ((timeCount == 4 && _isIntervalPattern(_selectedTimes, 6)) ||
        (timeCount == 4 && _isIntervalPattern(_selectedTimes, 4)) ||
        (timeCount == 3 && _isIntervalPattern(_selectedTimes, 8)) ||
        (timeCount == 2 && _isIntervalPattern(_selectedTimes, 12))) {
      if (_selectedTiming != 'Custom') {
        setState(() {
          _selectedTiming = 'Custom';
        });
        print('🔄 Auto-detected interval pattern, updated timing to: Custom');
      }
    }
  }

  void _removeTime(int index) {
    if (_selectedTimes.length > 1) {
      setState(() {
        _selectedTimes.removeAt(index);
      });
      
      // Sync frequency with times after removing
      _syncFrequencyWithTimes();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('At least one reminder time is required'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Widget _buildVoiceRecordingSection() {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mic, color: theme.primaryColor, size: 24),
              SizedBox(width: 8),
              Text(
                'Voice Instructions',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          Text(
            'Record voice instructions for this medicine reminder',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 16),
          
          // Voice recording controls
          Row(
            children: [
              // Record/Stop button with enhanced UX (hidden while playing)
              if (!_isPlaying)
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: GestureDetector(
                    onTap: _isRecording ? _stopRecording : _startRecording,
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : theme.primaryColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : theme.primaryColor).withOpacity(0.4),
                            blurRadius: _isRecording ? 12 : 8,
                            offset: Offset(0, 3),
                            spreadRadius: _isRecording ? 2 : 0,
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: Duration(milliseconds: 200),
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          key: ValueKey(_isRecording),
                          color: Colors.white,
                          size: _isRecording ? 32 : 28,
                        ),
                      ),
                    ),
                  ),
                ),
              
              // Add spacing only if record button is shown
              if (!_isPlaying) SizedBox(width: 16),
              
              // Recording status and duration with enhanced UX
              Expanded(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: Duration(milliseconds: 300),
                      child: Row(
                        key: ValueKey(_isRecording || _isPlaying),
                        children: [
                          if (_isRecording || _isPlaying) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isRecording ? Colors.red : Colors.blue,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          Text(
                            _isRecording ? 'Recording...' : 
                            _isPlaying ? 'Voice playing...' : 
                            (_voiceFilePath != null ? 'Voice recorded' : 'No voice recorded'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: _isRecording ? Colors.red : 
                                     _isPlaying ? Colors.blue : 
                                     (_voiceFilePath != null ? Colors.green : Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Play/Stop playback button with enhanced UX (hidden while recording)
              if (_voiceFilePath != null && !_isRecording) ...[
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: GestureDetector(
                    onTap: _isPlaying ? _stopPlayback : _playRecording,
                    child: Container(
                      width: 55,
                      height: 55,
                      decoration: BoxDecoration(
                        color: _isPlaying ? Colors.orange : Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isPlaying ? Colors.orange : Colors.green).withOpacity(0.4),
                            blurRadius: _isPlaying ? 10 : 6,
                            offset: Offset(0, 2),
                            spreadRadius: _isPlaying ? 1 : 0,
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: Duration(milliseconds: 200),
                        child: Icon(
                          _isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                          key: ValueKey(_isPlaying),
                          color: Colors.white,
                          size: _isPlaying ? 26 : 24,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Add spacing only if delete button is shown
                if (!_isPlaying) SizedBox(width: 12),
                
                // Delete recording button with enhanced UX (hidden while playing)
                if (!_isPlaying)
                  AnimatedContainer(
                    duration: Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: GestureDetector(
                      onTap: _deleteRecording,
                      child: Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.red.shade300,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withOpacity(0.1),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.delete_rounded,
                          color: Colors.red.shade600,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _isSaving ? null : _saveMedicine,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    _isEditMode ? 'Update Medicine' : 'Save Medicine',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField(
    String label, 
    String value, 
    List<String> items, 
    ValueChanged<String?> onChanged, {
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: enabled ? Colors.grey.shade100 : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: items.contains(value) ? value : items.first,
              isExpanded: true,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildValidatedTextField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    int maxLines = 1,
    String? Function(String?)? validator,
    InputDecoration? decoration,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          enabled: enabled,
          maxLines: maxLines,
          validator: validator,
          decoration: decoration ?? InputDecoration(
            filled: true,
            fillColor: enabled ? Colors.grey.shade100 : Colors.grey.shade200,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
            ),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDurationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Duration',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        
        // Toggle between calendar selection and manual input
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _useDateRange = true;
                    // Auto-calculate duration when switching to date range
                    if (_startDate != null && _endDate != null) {
                      final durationDays = TimingUtils.calculateDurationDays(_startDate!, _endDate!);
                      _durationController.text = '$durationDays days';
                    }
                  });
                },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: _useDateRange ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _useDateRange ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    'Calendar Selection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _useDateRange ? Theme.of(context).primaryColor : Colors.grey.shade600,
                      fontWeight: _useDateRange ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _useDateRange = false;
                  });
                },
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: !_useDateRange ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: !_useDateRange ? Theme.of(context).primaryColor : Colors.grey.shade300,
                    ),
                  ),
                  child: Text(
                    'Manual Input',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: !_useDateRange ? Theme.of(context).primaryColor : Colors.grey.shade600,
                      fontWeight: !_useDateRange ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
        
        // Show appropriate input method
        if (_useDateRange) ...[
          _buildDateRangeSelection(),
        ] else ...[
          TextFormField(
            controller: _durationController,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter duration';
              }
              
              // Try to parse the duration
              final parsedDays = DurationHelper.parseDurationToDays(value);
              
              // Check if it's an indefinite duration
              if (parsedDays == null) {
                // Check if it's a valid indefinite duration
                final isValidIndefinite = DurationHelper.indefinitePhrases.any(
                  (phrase) => value.toLowerCase().contains(phrase)
                );
                
                if (!isValidIndefinite) {
                  return 'Format not recognized. Try: "5 days", "2 weeks", "30 pills", or "till finished"';
                }
              }
              
              return null;
            },
            decoration: InputDecoration(
              hintText: 'e.g. 5d, 2 weeks, 30ps, till finished',
              helperText: 'Supports: days (d/ds), weeks (w), months (m), pills (p/ps), tablets (t/ts)',
              helperMaxLines: 2,
              prefixIcon: Icon(Icons.timelapse),
              filled: true,
              fillColor: Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onChanged: (value) {
              setState(() {}); // To update the preview below
            },
          ),
        ],
        
        // Real-time preview of parsed duration
        if (_durationController.text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Builder(
              builder: (context) {
                if (_useDateRange && _startDate != null && _endDate != null) {
                  final durationDays = TimingUtils.calculateDurationDays(_startDate!, _endDate!);
                  final display = TimingUtils.formatDateRange(_startDate!, _endDate!);
                  return Text(
                    'Duration: $display',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                } else {
                  final parsed = DurationHelper.parseDurationToDays(_durationController.text);
                  if (parsed != null) {
                    final display = DurationHelper.formatDurationDisplay(_durationController.text);
                    return Text(
                      'Understood as: $display',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  } else {
                    // Check if it's a valid indefinite duration
                    final isValidIndefinite = DurationHelper.indefinitePhrases.any(
                      (phrase) => _durationController.text.toLowerCase().contains(phrase)
                    );
                    
                    if (isValidIndefinite) {
                      return Text(
                        'Understood as: until finished',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    } else {
                      return Text(
                        'Invalid format - please check',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }
                  }
                }
              },
            ),
          ),
      ],
    );
  }

  // Helper method to safely convert any value to a string
  String _safeToString(dynamic value) {
    if (value == null) return '';
    
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else if (value is DateTime) {
      return value.toIso8601String();
    } else if (value is Map || value is List) {
      try {
        return jsonEncode(value);
      } catch (e) {
        return value.toString();
      }
    } else {
      return value.toString();
    }
  }

  Widget _buildDateRangeSelection() {
    return Column(
      children: [
        // Start Date Selection
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _selectDate(true),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade100,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: Colors.grey.shade600),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _startDate != null 
                                ? DateFormat('MMM dd, yyyy').format(_startDate!)
                                : 'Select start date',
                              style: TextStyle(
                                fontSize: 14,
                                color: _startDate != null ? Colors.black : Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _selectDate(false),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey.shade100,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, size: 20, color: Colors.grey.shade600),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'To',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _endDate != null 
                                ? DateFormat('MMM dd, yyyy').format(_endDate!)
                                : 'Select end date',
                              style: TextStyle(
                                fontSize: 14,
                                color: _endDate != null ? Colors.black : Colors.grey.shade500,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }



  Future<void> _selectDate(bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: isStartDate ? DateTime.now() : (_startDate ?? DateTime.now()),
      lastDate: DateTime.now().add(Duration(days: 365 * 2)), // 2 years from now
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          // Ensure end date is not before start date
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = picked;
          }
        } else {
          _endDate = picked;
        }
        
        // Update duration controller
        if (_startDate != null && _endDate != null) {
          final durationDays = TimingUtils.calculateDurationDays(_startDate!, _endDate!);
          _durationController.text = '$durationDays days';
        }
      });
    }
  }

  // Create new medicine with local-first approach for instant UI
  Future<String> _createMedicineWithLocalFirst(
    MedicineService medicineService,
    String userId,
    Map<String, dynamic> medicineData,
    int? durationDays,
  ) async {
    try {
      print('🚀 Creating new medicine with local-first approach');
      
      // Generate unique medicine ID
      final medicineId = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Prepare medicine data with schedule information
      final enhancedMedicineData = await _prepareMedicineDataWithSchedule(
        medicineData,
        durationDays,
      );
      
      // Save to local storage immediately for instant UI update
      await _saveMedicineToLocalStorage(
        userId,
        medicineId,
        enhancedMedicineData,
      );
      
      print('✅ New medicine created locally with ID: $medicineId');
      return medicineId;
      
    } catch (e) {
      print('❌ Error creating medicine locally: $e');
      throw e;
    }
  }

  // Prepare medicine data with schedule information
  Future<Map<String, dynamic>> _prepareMedicineDataWithSchedule(
    Map<String, dynamic> medicineData,
    int? durationDays,
  ) async {
    final enhancedData = Map<String, dynamic>.from(medicineData);
    
    if (durationDays != null && durationDays > 1) {
      // Duration-based medicine: Create schedule entries
      final List<Map<String, dynamic>> scheduleEntries = [];
      final List<String> scheduleDates = [];
      
      // Use calendar selection dates if available, otherwise use today
      DateTime startDate;
      if (_useDateRange && _startDate != null) {
        startDate = _startDate!;
      } else {
        startDate = DateTime.now();
      }
      
      for (int i = 0; i < durationDays; i++) {
        final scheduleDate = startDate.add(Duration(days: i));
        final dateString = DateFormat('yyyy-MM-dd').format(scheduleDate);
        
        scheduleEntries.add({
          'date': dateString,
          'time': medicineData['time'],
          'isCompleted': false,
          'completedAt': null,
        });
        
        scheduleDates.add(dateString);
      }
      
      enhancedData['scheduleDates'] = scheduleDates;
      enhancedData['scheduleData'] = scheduleEntries;
      enhancedData['totalDays'] = durationDays;
      enhancedData['startDate'] = DateFormat('yyyy-MM-dd').format(startDate);
      enhancedData['endDate'] = DateFormat('yyyy-MM-dd').format(startDate.add(Duration(days: durationDays - 1)));
      
    } else {
      // Single medicine: Create single schedule entry
      String scheduleDate;
      if (_useDateRange && _startDate != null) {
        scheduleDate = DateFormat('yyyy-MM-dd').format(_startDate!);
      } else {
        scheduleDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
      }
      
      enhancedData['scheduleDates'] = [scheduleDate];
      enhancedData['scheduleData'] = [{
        'date': scheduleDate,
        'time': medicineData['time'],
        'isCompleted': false,
        'completedAt': null,
      }];
      enhancedData['totalDays'] = 1;
      enhancedData['startDate'] = scheduleDate;
      enhancedData['endDate'] = scheduleDate;
    }
    
    // Add calendar selection info if using date range
    if (_useDateRange && _startDate != null && _endDate != null) {
      enhancedData['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
      enhancedData['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
      enhancedData['isCalendarSelection'] = true;
    }
    
    return enhancedData;
  }

  // Save medicine data to local storage for instant access
  Future<void> _saveMedicineToLocalStorage(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'medicine_${userId}_$medicineId';
      
      // Convert medicine data to JSON string
      final medicineJson = jsonEncode(medicineData);
      await prefs.setString(key, medicineJson);
      
      // Also save to a list of medicines for tracking
      final medicinesKey = 'medicines_$userId';
      List<String> medicines = prefs.getStringList(medicinesKey) ?? [];
      if (!medicines.contains(medicineId)) {
        medicines.add(medicineId);
        await prefs.setStringList(medicinesKey, medicines);
      }
      
      // Set last update timestamp
      await prefs.setString('last_medicine_update_$userId', DateTime.now().toIso8601String());
      
      print('💾 Saved new medicine to local storage with key: $key');
    } catch (e) {
      print('❌ Error saving to local storage: $e');
      throw e;
    }
  }

  // Sync new medicine to database in background
  void _syncNewMedicineToDatabase(
    MedicineService medicineService,
    String userId,
    String medicineId,
    Map<String, dynamic> medicineData,
    int? durationDays,
  ) {
    // Run in background without blocking UI
    Future.microtask(() async {
      try {
        print('🔄 Syncing new medicine to database: $medicineId');
        
        if (durationDays != null && durationDays > 1) {
          // Duration-based medicine: Use document-based approach
          final List<Map<String, dynamic>> medicineEntries = [];
          
          // Use calendar selection dates if available, otherwise use today
          DateTime startDate;
          if (_useDateRange && _startDate != null) {
            startDate = _startDate!;
          } else {
            startDate = DateTime.now();
          }
          
          for (int i = 0; i < durationDays; i++) {
            final scheduleDate = startDate.add(Duration(days: i));
            final dateString = DateFormat('yyyy-MM-dd').format(scheduleDate);
            
            final entryData = {
              ...medicineData,
              'scheduleDate': dateString,
              'isCompleted': false,
              'completedAt': null,
            };
            
            // Add calendar selection info if using date range
            if (_useDateRange && _startDate != null && _endDate != null) {
              entryData['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
              entryData['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
              entryData['isCalendarSelection'] = true;
            }
            
            medicineEntries.add(entryData);
          }
          
          await medicineService.saveMedicinesDocumentBased(
            userId,
            medicineEntries,
            {'id': 'manual_added', 'source': 'manual'},
          );
        } else {
          // Single medicine: Use document-based approach
          String scheduleDate;
          if (_useDateRange && _startDate != null) {
            scheduleDate = DateFormat('yyyy-MM-dd').format(_startDate!);
          } else {
            scheduleDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
          }
          
          final medicineEntry = {
            ...medicineData,
            'scheduleDate': scheduleDate,
            'isCompleted': false,
            'completedAt': null,
          };
          
          // Add calendar selection info if using date range
          if (_useDateRange && _startDate != null && _endDate != null) {
            medicineEntry['calendarStartDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
            medicineEntry['calendarEndDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
            medicineEntry['isCalendarSelection'] = true;
          }
          
          await medicineService.saveMedicinesDocumentBased(
            userId,
            [medicineEntry],
            {'id': 'manual_added', 'source': 'manual'},
          );
        }
        
        print('✅ New medicine synced to database successfully');
        
      } catch (e) {
        print('❌ Failed to sync new medicine to database: $e');
        // Schedule retry
        _scheduleRetry(userId, medicineId, medicineData);
      }
    });
  }
}

