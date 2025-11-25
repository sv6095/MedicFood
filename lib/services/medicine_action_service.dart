import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import '../screens/adherence_tracking_screen.dart';
import 'adherence_service.dart';
import 'dart:math';

class MedicineActionService {
  static const MethodChannel _channel = MethodChannel('notification_service');
  
  // Singleton pattern
  static final MedicineActionService _instance = MedicineActionService._internal();
  factory MedicineActionService() => _instance;
  MedicineActionService._internal();

  // Debouncing for UI notifications
  DateTime? _lastNotificationTime;
  
  // Deduplication cache to prevent double processing
  final Map<String, DateTime> _processedActions = {};
  static const Duration _deduplicationWindow = Duration(seconds: 5);

  // Normalize ID fields for consistency
  String normalizeId(dynamic id) {
    if (id == null) return '';
    return id.toString().trim();
  }
  
  // Validate payload structure
  bool _validatePayloadStructure(Map<String, dynamic> payload) {
    final requiredFields = ['medicineId', 'medicineName', 'date', 'time'];
    return requiredFields.every((field) => 
        payload.containsKey(field) && 
        payload[field] != null && 
        payload[field].toString().isNotEmpty
    );
  }
  
  // Validation utilities
  bool _isValidDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return false;
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    return dateRegex.hasMatch(dateStr);
  }
  
  bool _isValidTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return false;
    final timeRegex = RegExp(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$');
    return timeRegex.hasMatch(timeStr);
  }
  
  String _normalizeDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) {
      return DateFormat('yyyy-MM-dd').format(DateTime.now());
    }
    
    if (_isValidDate(rawDate)) return rawDate;
    
    try {
      // Try US format MM/DD/YYYY
      if (rawDate.contains('/')) {
        final parts = rawDate.split('/');
        if (parts.length == 3) {
          final month = parts[0].padLeft(2, '0');
          final day = parts[1].padLeft(2, '0');
          String year = parts[2];
          if (year.length == 2) year = '20$year'; // Assume 20xx for 2-digit years
          
          final fixedDate = '$year-$month-$day';
          if (_isValidDate(fixedDate)) {
            return fixedDate;
          }
        }
      } 
      // Try parse with DateTime
      else {
        final dateTime = DateTime.parse(rawDate);
        return DateFormat('yyyy-MM-dd').format(dateTime);
      }
    } catch (e) {
      print('⚠️ MedicineActionService: Could not normalize date: $rawDate, using current date');
    }
    
    return DateFormat('yyyy-MM-dd').format(DateTime.now());
  }
  
  String _normalizeTime(String? rawTime) {
    // Return current time if null or empty
    if (rawTime == null || rawTime.isEmpty) {
      return DateFormat('HH:mm').format(DateTime.now());
    }
    
    // Return as-is if already valid
    if (_isValidTime(rawTime)) return rawTime;
    
    try {
      // Check for 12-hour format (with AM/PM)
      if (rawTime.toLowerCase().contains('am') || rawTime.toLowerCase().contains('pm')) {
        for (var format in ['h:mm a', 'hh:mm a', 'h:mma', 'hh:mma']) {
          try {
            return DateFormat('HH:mm').format(DateFormat(format).parse(rawTime));
          } catch (_) {}
        }
      } 
      // Handle time with colon (24-hour format)
      else if (rawTime.contains(':')) {
        final parts = rawTime.split(':');
        if (parts.length == 2) {
          final hour = parts[0].padLeft(2, '0');
          final minute = parts[1].padLeft(2, '0');
          final fixedTime = '$hour:$minute';
          if (_isValidTime(fixedTime)) return fixedTime;
        }
      }
      // Handle military time (e.g., "0930")
      else if (rawTime.length == 4 && int.tryParse(rawTime) != null) {
        final hour = rawTime.substring(0, 2);
        final minute = rawTime.substring(2, 4);
        final fixedTime = '$hour:$minute';
        if (_isValidTime(fixedTime)) return fixedTime;
      }
    } catch (e) {
      // Use current time as fallback
    }
    
    // Default fallback to current time
    return DateFormat('HH:mm').format(DateTime.now());
  }
  
  String _normalizeActionType(String? actionType) {
    if (actionType == null || actionType.isEmpty) return 'unknown';
    
    final normalizedAction = actionType.toLowerCase();
    
    // Exact match
    if (['taken', 'missed', 'skipped', 'postponed'].contains(normalizedAction)) {
      return normalizedAction;
    }
    
    // Fuzzy match
    if (normalizedAction.contains('take') || normalizedAction.contains('took')) {
      return 'taken';
    } else if (normalizedAction.contains('miss') || normalizedAction.contains('fail')) {
      return 'missed';
    } else if (normalizedAction.contains('skip') || normalizedAction.contains('pass')) {
      return 'skipped';
    } else if (normalizedAction.contains('post') || normalizedAction.contains('delay') || 
               normalizedAction.contains('later')) {
      return 'postponed';
    }
    
    return 'unknown';
  }
  
  // Comprehensive validation for medicine action data
  bool _validateMedicineAction(Map<String, dynamic> action, {bool autoFix = true}) {
    final requiredFields = ['medicineId', 'medicineName', 'date', 'time', 'action'];
    
    if (autoFix) {
      // Normalize and fix core fields
      action['date'] = _normalizeDate(action['date']?.toString());
      action['time'] = _normalizeTime(action['time']?.toString());
      action['action'] = _normalizeActionType(action['action']?.toString());
      
      // Fix ID fields
      final medicineId = normalizeId(action['medicineId'] ?? action['id']);
      action['medicineId'] = medicineId.isNotEmpty 
          ? medicineId 
          : action.containsKey('medicineName') && action['medicineName'] != null
              ? '${action['medicineName']}_${DateTime.now().millisecondsSinceEpoch}'
              : 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      
      // Fix medicine name
      if (!action.containsKey('medicineName') || 
          action['medicineName'] == null || 
          action['medicineName'].toString().isEmpty) {
        action['medicineName'] = action.containsKey('name') && action['name'] != null 
            ? action['name'] 
            : 'Unknown Medicine';
      }
      
      // Fix actionId if needed
      if (!action.containsKey('actionId') || 
          action['actionId'] == null || 
          action['actionId'].toString().isEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        action['actionId'] = '${action['medicineId']}_${action['date']}_${action['time'].toString().replaceAll(':', '_')}_$timestamp';
      }
    }
    
    // Check if all required fields are now present and valid
    return requiredFields.every((field) => 
      action.containsKey(field) && 
      action[field] != null && 
      action[field].toString().isNotEmpty
    );
  }

  // Callback for medicine action updates
  Function(Map<String, dynamic>)? onMedicineActionReceived;
  
  // Global key for UI updates
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Cache management
  static const int _cacheValidityMinutes = 0; // Reduced to 0 to always get fresh data
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  // Initialize the service and set up method channel
  void initialize() {
    print('🚀 MedicineActionService: Initializing service');
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('🔔 MedicineActionService: Method call received: ${call.method}');
    try {
      Map<String, dynamic> arguments = {};
      
      // Safely convert incoming arguments to the correct types
      if (call.arguments is Map<dynamic, dynamic>) {
        // Convert dynamic map to string map
        (call.arguments as Map<dynamic, dynamic>).forEach((key, value) {
          if (key is String) {
            arguments[key] = value;
          }
        });
      } else if (call.arguments is Map<String, dynamic>) {
        arguments = call.arguments as Map<String, dynamic>;
      } else {
        print('⚠️ MedicineActionService: Invalid arguments type: ${call.arguments.runtimeType}');
        return;
      }
      
      // Log the prepared arguments
      print('📦 MedicineActionService: Prepared arguments: $arguments');
      
    switch (call.method) {
      case 'medicineActionTaken':
        print('✅ MedicineActionService: Received taken action');
          await _handleMedicineAction(arguments, 'taken');
        break;
      case 'medicineActionMissed':
        print('❌ MedicineActionService: Received missed action');
          await _handleMedicineAction(arguments, 'missed');
        break;
      case 'medicineActionSkipped':
        print('⏭️ MedicineActionService: Received skipped action');
          await _handleMedicineAction(arguments, 'skipped');
        break;
      case 'medicineActionPostponed':
        print('⏳ MedicineActionService: Received postponed action');
          await _handlePostponedMedicine(arguments);
        break;
      default:
        print('❓ MedicineActionService: Unknown method call: ${call.method}');
    }
    } catch (e) {
      print('❌ MedicineActionService: Error handling method call: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
    }
  }

  // Handle medicine action and store locally with unified approach
  Future<void> _handleMedicineAction(Map<String, dynamic> data, String action) async {
    try {
      // CRITICAL: Ensure snooze actions are never processed as adherence actions
      if (action.toLowerCase() == 'snooze') {
        print('⚠️ MedicineActionService: Snooze action detected, skipping adherence tracking');
        return;
      }
      
      // Create a clean copy of the data
      Map<String, dynamic> medicineData = Map<String, dynamic>.from(data);
      print('📥 MedicineActionService: Processing ${action} action');
      print('📄 MedicineActionService: Received data: ${medicineData.toString()}');
      
      // Create a unique key for deduplication
      final medicineId = normalizeId(medicineData['medicineId'] ?? medicineData['id'] ?? '');
      final date = medicineData['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
      final time = medicineData['time'] ?? DateFormat('HH:mm').format(DateTime.now());
      final deduplicationKey = '${medicineId}_${date}_${time.replaceAll(':', '_')}_$action';
      
      // Check if this action was recently processed
      final now = DateTime.now();
      if (_processedActions.containsKey(deduplicationKey)) {
        final lastProcessed = _processedActions[deduplicationKey]!;
        if (now.difference(lastProcessed) < _deduplicationWindow) {
          print('🔄 MedicineActionService: Action recently processed, skipping duplicate: $deduplicationKey');
          return;
        }
      }
      
      // Mark this action as processed
      _processedActions[deduplicationKey] = now;
      
      // Clean up old entries (older than 1 hour)
      _processedActions.removeWhere((key, timestamp) => 
        now.difference(timestamp) > Duration(hours: 1));
      
      // Get user ID from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || userId.isEmpty) {
        throw Exception('User ID not found. Please restart the app or re-enter your name.');
      }
      medicineData['userId'] = userId;
      
      // Ensure medicineId is present and normalized
      if (medicineData.containsKey('medicineId')) {
        medicineData['medicineId'] = normalizeId(medicineData['medicineId']);
      } else if (medicineData.containsKey('id')) {
        medicineData['medicineId'] = normalizeId(medicineData['id']);
      }
      
      // Process payload if available
      if (medicineData.containsKey('payload') && medicineData['payload'] is String && 
          medicineData['payload'].toString().isNotEmpty) {
        _processPayload(medicineData, action);
      }
      
      // Set action type and timestamp
      medicineData['action'] = action;
      medicineData['recordedAt'] = DateTime.now().toIso8601String();
      
      // Validate and normalize all data fields
      final isValid = _validateMedicineAction(medicineData, autoFix: true);
      print('🔍 MedicineActionService: Validation result: $isValid');
      print('🔍 MedicineActionService: After validation: ${medicineData.toString()}');
      
      // Create unique action ID if needed
      if (!medicineData.containsKey('actionId') || medicineData['actionId'] == null || medicineData['actionId'].toString().isEmpty) {
        final medicineId = medicineData['medicineId'] as String;
        final actionDate = medicineData['date'] as String;
        final actionTime = medicineData['time'] as String;
        medicineData['actionId'] = '${medicineId}_${actionDate}_${actionTime.replaceAll(':', '_')}';
      }
      
      // Store action
      await _storeMedicineAction(medicineData);
      
      // Notify UI
      clearCache();
      _notifyUIUpdate();
      
      print('✅ MedicineActionService: Action recorded: $action - ${medicineData['medicineName']}');
    } catch (e) {
      print('❌ MedicineActionService: Error handling medicine action: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
    }
  }
  
  // Process JSON payload from a medicine action
  void _processPayload(Map<String, dynamic> medicineData, String originalAction) {
    try {
      final String payloadStr = medicineData['payload'].toString();
      print('🧩 MedicineActionService: Processing payload');
      
      if (!payloadStr.startsWith('{') || !payloadStr.endsWith('}')) {
        print('⚠️ MedicineActionService: Payload does not appear to be JSON');
        return;
      }

      final payloadMap = jsonDecode(payloadStr);
      if (payloadMap is! Map<String, dynamic>) {
        print('⚠️ MedicineActionService: Payload JSON is not a Map');
        return;
      }

      // Validate payload structure
      final isValidPayload = _validatePayloadStructure(payloadMap);
      
      if (isValidPayload) {
        print('✅ MedicineActionService: Valid payload found');
        // Merge data, with payload taking precedence for most fields
        medicineData.addAll(payloadMap);
      } else {
        print('⚠️ MedicineActionService: Using partial payload data');
        // Only copy fields that exist and are not empty
        payloadMap.forEach((key, value) {
          if (value != null && value.toString().isNotEmpty) {
            medicineData[key] = value;
          }
        });
      }
      
      // Preserve original action type
      medicineData['action'] = originalAction;
      
    } catch (e) {
      print('⚠️ MedicineActionService: Failed to process payload: $e');
    }
  }
  
  // Handle postponed medicine by reusing shared functionality
  Future<void> _handlePostponedMedicine(Map<String, dynamic> data) async {
    try {
      print('⏳ MedicineActionService: Handling postponed medicine');
      
      // Create a copy of data to work with
      final medicineData = Map<String, dynamic>.from(data);
      
      // First, use the core action handler with postponed action type
      await _handleMedicineAction(medicineData, 'postponed');
      
      // Then also store in postponed-specific storage for quick lookup
      try {
        final prefs = await SharedPreferences.getInstance();
        final medicineId = medicineData['medicineId'] as String;
        final date = medicineData['date'] as String;
        final postponedKey = 'postponed_medicine_${medicineId}_$date';
        medicineData['postponedAt'] = DateTime.now().toIso8601String();
        
        // Store postponed medicine separately
        await prefs.setString(postponedKey, jsonEncode(medicineData));
      } catch (e) {
        print('⚠️ MedicineActionService: Error storing postponed data: $e');
      }
      
      print('✅ MedicineActionService: Medicine postponed successfully');
    } catch (e) {
      print('❌ MedicineActionService: Error handling postponed medicine: $e');
    }
  }

  // Store medicine action locally and in database
  Future<void> _storeMedicineAction(Map<String, dynamic> actionData) async {
    try {
      print('💾 MedicineActionService: Storing action data');
      final prefs = await SharedPreferences.getInstance();
      
      // Debug: Log all keys and values before validation
      print('🔑 MedicineActionService: Action data keys before validation:');
      actionData.forEach((key, value) {
        print('   $key: ${value.runtimeType} = $value');
      });
      
      // Extract original medicine ID from composite ID if needed
      String originalMedicineId = actionData['medicineId'] ?? '';
      String compositeId = originalMedicineId;
      
      if (originalMedicineId.contains('_') && actionData.containsKey('date')) {
        final date = actionData['date'] as String;
        if (originalMedicineId.endsWith('_$date')) {
          originalMedicineId = originalMedicineId.substring(0, originalMedicineId.lastIndexOf('_'));
          print('🔧 MedicineActionService: Extracted original medicine ID: $originalMedicineId from composite: $compositeId');
        }
      }
      
      // Ensure required fields are present with fallbacks
      final requiredFields = {
        'actionId': () => '${DateTime.now().millisecondsSinceEpoch}_${actionData['medicineName'] ?? 'unknown'}',
        'medicineId': () => originalMedicineId.isNotEmpty ? originalMedicineId : 'unknown_${DateTime.now().millisecondsSinceEpoch}',
        'medicineName': () => actionData['name'] ?? 'Unknown Medicine',
        'date': () => _normalizeDate(null), // Uses current date
        'time': () => _normalizeTime(null), // Uses current time
        'action': () => _normalizeActionType(actionData['action'] ?? 'unknown')
      };
      
      // Fix missing fields
      bool hasAllFields = true;
      requiredFields.forEach((field, fallbackFn) {
        if (!actionData.containsKey(field) || 
            actionData[field] == null || 
            actionData[field].toString().isEmpty) {
          print('⚠️ MedicineActionService: Fixing missing/empty field: $field');
          actionData[field] = fallbackFn();
          hasAllFields = false;
        }
      });
      
      // Update medicineId to use the original ID
      actionData['medicineId'] = originalMedicineId;
      actionData['originalCompositeId'] = compositeId; // Store the original composite ID
      
      if (!hasAllFields) {
        print('⚠️ MedicineActionService: Had to fix missing fields in the action data');
        print('🔧 MedicineActionService: Fixed data: $actionData');
      }
      
      // Clean data for storage and ensure it's serializable
      final cleanActionData = <String, dynamic>{};
      actionData.forEach((key, value) {
        // Only keep serializable values
        if (value is String || value is num || value is bool || value == null) {
          cleanActionData[key] = value;
        } else {
          try {
            // Try to convert complex types via JSON serialization
            cleanActionData[key] = jsonDecode(jsonEncode(value));
          } catch (e) {
            print('⚠️ MedicineActionService: Could not serialize field $key: $e');
            // Skip non-serializable values
          }
        }
      });
      
      // Save to database using AdherenceService
      await _saveToDatabase(cleanActionData);
      
      // Get existing actions with error handling
      List<dynamic> actions = [];
      try {
        actions = jsonDecode(prefs.getString('medicine_actions') ?? '[]');
        if (actions is! List) {
          print('⚠️ MedicineActionService: Stored actions is not a List, resetting');
          actions = [];
        }
      } catch (e) {
        print('⚠️ MedicineActionService: Error parsing stored actions: $e');
        // Reset on parse error
        actions = [];
      }
      
      // Check for duplicate action to prevent double counting
      final actionId = normalizeId(cleanActionData['actionId']);
      final medicineId = normalizeId(cleanActionData['medicineId']);
      final date = cleanActionData['date'] as String;
      final time = cleanActionData['time'] as String;
      final action = cleanActionData['action'] as String;
      
      // Create a unique key for this action to prevent duplicates
      final uniqueKey = '${medicineId}_${date}_${time.replaceAll(':', '_')}';
      
      // Check if this exact action already exists by actionId
      final existingIndex = actions.indexWhere((action) => 
        action is Map && 
        normalizeId(action['actionId']) == actionId);
      
      if (existingIndex >= 0) {
        // Update existing action if it's different
        final existingAction = actions[existingIndex] as Map<String, dynamic>;
        if (existingAction['action'] != action) {
          actions[existingIndex] = cleanActionData;
          print('🔄 MedicineActionService: Updated existing action: $actionId (action changed from ${existingAction['action']} to $action)');
        } else {
          print('ℹ️ MedicineActionService: Action already exists with same status, skipping: $actionId');
          return; // Don't proceed with further updates
        }
      } else {
        // Check for duplicate by unique key (medicine, date, and time combination)
        final duplicateIndex = actions.indexWhere((action) => 
          action is Map && 
          normalizeId(action['medicineId']) == medicineId &&
          action['date'] == date &&
          action['time'] == time);
        
        if (duplicateIndex >= 0) {
          // Check if the duplicate has the same action type
          final duplicateAction = actions[duplicateIndex] as Map<String, dynamic>;
          if (duplicateAction['action'] == action) {
            print('ℹ️ MedicineActionService: Duplicate action with same status already exists, skipping: $uniqueKey');
            return; // Don't proceed with further updates
          } else {
            // Update the duplicate with new action
            actions[duplicateIndex] = cleanActionData;
            print('🔄 MedicineActionService: Updated duplicate action: $uniqueKey (action changed from ${duplicateAction['action']} to $action)');
          }
        } else {
          actions.add(cleanActionData);
          print('➕ MedicineActionService: Added new action: $actionId for $uniqueKey');
        }
      }
      
      // Limit to 1000 most recent actions
      if (actions.length > 1000) {
        actions.removeRange(0, actions.length - 1000);
      }
      
      // Save with backup strategy
      try {
        // Create backup first 
        final existingData = prefs.getString('medicine_actions');
        if (existingData != null) {
          await prefs.setString('medicine_actions_backup', existingData);
        }
        
        // Save new data
        final jsonData = jsonEncode(actions);
        await prefs.setString('medicine_actions', jsonData);
        print('✅ MedicineActionService: Successfully saved ${actions.length} actions');
        
        // Clear backup on success
        await prefs.remove('medicine_actions_backup');
        
        // Update daily summary statistics
        await _updateDailySummary(cleanActionData);
        
        // Clear cache to ensure fresh data for summaries
        clearCache();
        
    } catch (e) {
        print('❌ MedicineActionService: Error saving: $e');
        // Try restore from backup if available
        if (prefs.containsKey('medicine_actions_backup')) {
          await prefs.setString('medicine_actions', 
              prefs.getString('medicine_actions_backup') ?? '[]');
        }
      }
    } catch (e) {
      print('❌ MedicineActionService: Error in action storage: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
    }
  }

  // Save medicine action to database
  Future<void> _saveToDatabase(Map<String, dynamic> actionData) async {
    try {
      print('💾 MedicineActionService: Saving to database');
      
      // Get user ID from action data or SharedPreferences
      String? userId = actionData['userId'] as String?;
      
      // If userId is not in action data, try to get it from SharedPreferences
      if (userId == null || userId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getString('user_id');
        if (userId == null || userId.isEmpty) {
          throw Exception('User ID not found. Please restart the app or re-enter your name.');
        }
      }
      
      final adherenceService = AdherenceService();
      
      await adherenceService.saveMedicineActionDocumentBased(
        userId: userId,
        medicineId: actionData['medicineId'] as String,
        medicineName: actionData['medicineName'] as String,
        action: actionData['action'] as String,
        date: actionData['date'] as String,
        time: actionData['time'] as String?,
        notes: actionData['notes'] as String?,
        medicineData: actionData,
      );
      
      print('✅ MedicineActionService: Successfully saved to database');
    } catch (e) {
      print('❌ MedicineActionService: Error saving to database: $e');
      // Don't throw here to avoid breaking local storage
    }
  }

  // Update daily summary statistics
  Future<void> _updateDailySummary(Map<String, dynamic> actionData) async {
    try {
      print('📊 MedicineActionService: Updating daily summary');
      final prefs = await SharedPreferences.getInstance();
      
      // Ensure we have the required fields
      final date = actionData['date'] as String;
      final action = actionData['action'] as String;
      
      // Get medicine ID using normalizeId
      String medicineId = normalizeId(actionData['medicineId'] ?? actionData['id']);
      if (medicineId.isEmpty) {
        print('❌ MedicineActionService: Missing medicine ID for daily summary');
        return;
      }
      
      // Always update medicineId in the action data for consistency
      actionData['medicineId'] = medicineId;
      
      print('🔍 MedicineActionService: Updating summary for date: $date, medicine: $medicineId, action: $action');
      
      // Get existing daily summary with safe parsing
      final summaryJson = prefs.getString('daily_adherence_summary') ?? '{}';
      final summary = _safelyParseJson(summaryJson);
      
      // Initialize date entry if not exists
      if (!summary.containsKey(date)) {
        summary[date] = {
          'taken': 0,
          'missed': 0,
          'skipped': 0,
          'total': 0,
          'medicines': <String, dynamic>{},
        };
        print('🆕 MedicineActionService: Created new summary entry for date: $date');
      }
      
      // Ensure the medicines map exists
      if (!summary[date].containsKey('medicines')) {
        summary[date]['medicines'] = <String, dynamic>{};
      }
      
      // Make sure we have a proper Map<String, dynamic>
      final medicines = summary[date]['medicines'] as Map<String, dynamic>;
      
      print('📊 MedicineActionService: Before update - taken: ${summary[date]['taken']}, missed: ${summary[date]['missed']}, skipped: ${summary[date]['skipped']}, total: ${summary[date]['total']}');
      
      // Check if this medicine already has an action recorded for this date
      if (!medicines.containsKey(medicineId)) {
        // First action for this medicine today - increment counts
        summary[date][action] = (summary[date][action] as int) + 1;
        summary[date]['total'] = (summary[date]['total'] as int) + 1;
        print('➕ MedicineActionService: First action for medicine, incrementing $action count');
      } else if (medicines[medicineId] != action) {
        // Action type changed - update the counts
        final oldAction = medicines[medicineId];
        summary[date][oldAction] = (summary[date][oldAction] as int) - 1;
        summary[date][action] = (summary[date][action] as int) + 1;
        print('🔄 MedicineActionService: Updated action from $oldAction to $action');
      } else {
        // Same action already recorded - no change needed
        print('ℹ️ MedicineActionService: Medicine already has same action recorded, no change needed');
        return; // Exit early to prevent unnecessary saves
      }
      
      // Update the medicine's status for this date
      medicines[medicineId] = action;
      summary[date]['medicines'] = medicines;
      
      print('📊 MedicineActionService: After update - taken: ${summary[date]['taken']}, missed: ${summary[date]['missed']}, skipped: ${summary[date]['skipped']}, total: ${summary[date]['total']}');
      
      // Save updated summary
      try {
        final newSummaryJson = jsonEncode(summary);
        await prefs.setString('daily_adherence_summary', newSummaryJson);
        print('✅ MedicineActionService: Updated daily summary successfully');
      } catch (e) {
        print('❌ MedicineActionService: Error saving daily summary: $e');
      }
      
    } catch (e) {
      print('❌ MedicineActionService: Error updating daily summary: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
    }
  }

  // Force refresh cache for specific keys
  void forceRefreshCache([List<String>? keys]) {
    if (keys != null) {
      for (final key in keys) {
        _cache.remove(key);
        _cacheTimestamps.remove(key);
      }
    } else {
      clearCache();
    }
  }

  // Get all medicine actions with caching, error recovery, and performance optimization
  Future<List<Map<String, dynamic>>> getAllMedicineActions() async {
    try {
      print('🔍 MedicineActionService: Getting all medicine actions');
      const cacheKey = 'all_medicine_actions';
      
      // Always get fresh data since cache validity is 0
      print('📦 MedicineActionService: Getting fresh actions data (cache disabled)');
      
      // Step 2: Get data from SharedPreferences with error handling
      final prefs = await SharedPreferences.getInstance();
      String? actionsJson;
      try {
        actionsJson = prefs.getString('medicine_actions');
      } catch (e) {
        print('⚠️ MedicineActionService: Error reading from SharedPreferences: $e');
        try {
          await prefs.remove('medicine_actions');
          print('🔄 MedicineActionService: Removed potentially corrupted medicine_actions data');
          return [];
        } catch (clearError) {
          print('❌ MedicineActionService: Failed to clear medicine_actions: $clearError');
          return [];
        }
      }

      // Step 3: Handle empty or missing data
      if (actionsJson == null || actionsJson.isEmpty) {
        print('ℹ️ MedicineActionService: No medicine actions found');
        return [];
      }

      // Step 4: Parse JSON with error handling
      List<dynamic> actions = [];
      try {
        actions = jsonDecode(actionsJson);
        if (actions is! List) {
          print('⚠️ MedicineActionService: Invalid actions format, returning empty list');
          // Clear corrupted data
          await prefs.remove('medicine_actions');
          print('🔄 MedicineActionService: Cleared corrupted medicine_actions (not a List)');
          return [];
        }
      } catch (e) {
        print('❌ MedicineActionService: Error parsing actions JSON: $e');
        // Try to recover by clearing corrupted data
        try {
          await prefs.remove('medicine_actions');
          print('🔄 MedicineActionService: Removed corrupted medicine_actions JSON after parse error');
          
          // Try to restore from backup if available
          if (prefs.containsKey('medicine_actions_backup')) {
            try {
              final backupJson = prefs.getString('medicine_actions_backup');
              if (backupJson != null && backupJson.isNotEmpty) {
                final backupActions = jsonDecode(backupJson);
                if (backupActions is List) {
                  print('🔄 MedicineActionService: Restored from backup successfully');
                  actions = backupActions;
                }
              }
            } catch (backupError) {
              print('❌ MedicineActionService: Failed to restore from backup: $backupError');
              return [];
            }
          } else {
            return [];
          }
        } catch (clearError) {
          print('❌ MedicineActionService: Failed to clear medicine_actions after parse error: $clearError');
          return [];
        }
      }

      // Step 5: Convert to List<Map<String, dynamic>> and validate each action
      final validActions = <Map<String, dynamic>>[];
      int invalidCount = 0;
      for (final action in actions) {
        if (action is! Map<String, dynamic>) {
          invalidCount++;
          continue;
        }
        
        try {
          // Attempt to sanitize the action before validation
          final sanitizedAction = _sanitizeActionData(action);
          
          if (_isValidMedicineAction(sanitizedAction)) {
            validActions.add(Map<String, dynamic>.from(sanitizedAction));
          } else {
            invalidCount++;
          }
        } catch (e) {
          print('⚠️ MedicineActionService: Error processing action: $e');
          invalidCount++;
        }
      }

      // Step 6: Cache valid results
      if (validActions.isNotEmpty) {
        try {
          _cache[cacheKey] = List<Map<String, dynamic>>.from(validActions);
          _cacheTimestamps[cacheKey] = DateTime.now();
        } catch (e) {
          print('⚠️ MedicineActionService: Error caching actions: $e');
        }
      }

      // Step 7: Log statistics and return valid actions
      print('📊 MedicineActionService: Found ${validActions.length} valid actions and $invalidCount invalid actions');
      return validActions;
    } catch (e) {
      print('❌ MedicineActionService: Critical error getting medicine actions: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
      
      // Emergency recovery - clear cache and corrupt data
      try {
        _cache.remove('all_medicine_actions');
        _cacheTimestamps.remove('all_medicine_actions');
        
        final prefs = await SharedPreferences.getInstance();
        // Before removing, try to back up the data for offline analysis
        final corruptedData = prefs.getString('medicine_actions');
        if (corruptedData != null && corruptedData.isNotEmpty) {
          await prefs.setString('medicine_actions_corrupted_backup', corruptedData);
        }
        await prefs.remove('medicine_actions');
        print('🔄 MedicineActionService: Cleared medicine_actions after critical error');
      } catch (_) {}
      
      return [];
    }
  }

  // Helper method to sanitize action data
  Map<String, dynamic> _sanitizeActionData(Map<String, dynamic> action) {
    final sanitized = <String, dynamic>{};
    
    // Copy and normalize key fields
    action.forEach((key, value) {
      if (value == null) {
        sanitized[key] = null;
        return;
      }
      
      switch (key) {
        case 'date':
          sanitized[key] = _normalizeDate(value.toString());
          break;
        case 'time':
          sanitized[key] = _normalizeTime(value.toString());
          break;
        case 'action':
          sanitized[key] = _normalizeActionType(value.toString());
          break;
        case 'medicineId':
        case 'id':
          // Normalize ID fields
          final normalizedId = normalizeId(value);
          if (normalizedId.isNotEmpty) {
            sanitized['medicineId'] = normalizedId;
          }
          break;
        default:
          // For primitive types, copy as is
          if (value is String || value is num || value is bool) {
            sanitized[key] = value;
          } 
          // For maps and lists, sanitize recursively if needed
          else if (value is Map || value is List) {
            try {
              // Convert to JSON and back to ensure only serializable values
              final jsonStr = jsonEncode(value);
              sanitized[key] = jsonDecode(jsonStr);
            } catch (e) {
              // Skip non-serializable complex values
            }
          }
      }
    });
    
    // Auto-fix required fields
    _validateMedicineAction(sanitized, autoFix: true);
    
    return sanitized;
  }

  bool _isValidMedicineAction(dynamic action) {
    if (action is! Map<String, dynamic>) {
      print('❌ MedicineActionService: Invalid action - not a Map<String, dynamic>');
      return false;
    }
    
    // Print the action for debugging
    print('🔍 MedicineActionService: Validating action: ${action.toString().substring(0, min(100, action.toString().length))}...');
    
    // Using our comprehensive validation with auto-fixing
    final isValid = _validateMedicineAction(action, autoFix: true);
    
    if (isValid) {
      print('✅ MedicineActionService: Action is valid');
    } else {
      print('❌ MedicineActionService: Action validation failed');
    }
    
    return isValid;
  }

  // Get medicine actions for a specific date range
  Future<List<Map<String, dynamic>>> getMedicineActionsForDateRange(String startDate, String endDate) async {
    try {
      final allActions = await getAllMedicineActions();
      
      // Parse the date strings to DateTime objects for proper comparison
      final startDateTime = DateFormat('yyyy-MM-dd').parse(startDate);
      final endDateTime = DateFormat('yyyy-MM-dd').parse(endDate);
      
      return allActions.where((action) {
        final actionDateStr = action['date'] as String;
        final actionDateTime = DateFormat('yyyy-MM-dd').parse(actionDateStr);
        return actionDateTime.isAfter(startDateTime.subtract(const Duration(days: 1))) && 
               actionDateTime.isBefore(endDateTime.add(const Duration(days: 1)));
      }).toList();
    } catch (e) {
      print('Error getting medicine actions for date range: $e');
      return [];
    }
  }

  // Get daily adherence summary
  Future<Map<String, dynamic>> getDailyAdherenceSummary() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final summaryJson = prefs.getString('daily_adherence_summary') ?? '{}';
      
      // Use our safe parsing helper
      final summary = _safelyParseJson(summaryJson);
      
      // Validate and clean up summary data
      final validSummary = <String, dynamic>{};
      
      summary.forEach((date, data) {
        if (_isValidDailySummary(date, data)) {
          validSummary[date] = data;
        } else {
          print('⚠️ MedicineActionService: Invalid summary data for date $date');
        }
      });
      
      return validSummary;
    } catch (e) {
      print('❌ MedicineActionService: Error getting daily summary: $e');
      print('❌ MedicineActionService: Stack trace: ${StackTrace.current}');
      return {};
    }
  }

  bool _isValidDailySummary(String date, dynamic data) {
    // Make sure we're handling generic Map rather than strict Map<String, dynamic>
    if (data is! Map) return false;
    
    // Validate date format
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(date)) return false;
    
    // Required fields with numeric values
    final requiredNumericFields = ['taken', 'missed', 'skipped', 'total'];
    for (final field in requiredNumericFields) {
      if (!data.containsKey(field) || data[field] is! num) {
        return false;
      }
    }
    
    // Validate medicines map
    if (!data.containsKey('medicines') || data['medicines'] is! Map) {
      return false;
    }
    
    return true;
  }

  // Get adherence statistics for a date range with caching
  Future<Map<String, dynamic>> getAdherenceStatistics({String? startDate, String? endDate}) async {
    try {
      // Create a cache key based on date range
      final cacheKey = 'adherence_stats_${startDate ?? 'all'}_${endDate ?? 'all'}';
      
      // Check if we have a valid cache
      if (_isCacheValid(cacheKey)) {
        print('📦 MedicineActionService: Using cached adherence statistics');
        return Map<String, dynamic>.from(_cache[cacheKey]);
      }
      
      final actions = startDate != null && endDate != null
          ? await getMedicineActionsForDateRange(startDate, endDate)
          : await getAllMedicineActions();

      // Group actions by date and medicineId to count unique medicine takes per day
      final actionsByDateAndMedicine = <String, Map<String, String>>{};
      
      for (var action in actions) {
        final date = action['date'] as String;
        final medicineId = action['medicineId'] ?? action['id'] ?? '';
        final actionType = action['action'] as String;
        final key = '${date}_$medicineId';
        
        // Only update if this is the first action for this medicine on this date
        // or if the current action is 'taken' (prioritize 'taken' over other statuses)
        if (!actionsByDateAndMedicine.containsKey(key) || 
            actionType == 'taken' ||
            (actionType == 'missed' && actionsByDateAndMedicine[key]!['action'] == 'skipped')) {
          actionsByDateAndMedicine[key] = {
            'action': actionType,
            'date': date,
            'medicineId': medicineId
          };
        }
      }

      // Count totals from the grouped actions
      int totalTaken = 0;
      int totalMissed = 0;
      int totalSkipped = 0;

      actionsByDateAndMedicine.values.forEach((action) {
        switch (action['action']) {
          case 'taken':
            totalTaken++;
            break;
          case 'missed':
            totalMissed++;
            break;
          case 'skipped':
            totalSkipped++;
            break;
        }
      });

      final totalScheduled = totalTaken + totalMissed + totalSkipped;
      final adherenceRate = totalScheduled > 0 ? (totalTaken / totalScheduled) * 100 : 0.0;

      final result = {
        'totalTaken': totalTaken,
        'totalMissed': totalMissed,
        'totalSkipped': totalSkipped,
        'totalScheduled': totalScheduled,
        'adherenceRate': adherenceRate,
        'period': {
          'startDate': startDate,
          'endDate': endDate,
        },
      };
      
      // Cache the result
      _cache[cacheKey] = result;
      _cacheTimestamps[cacheKey] = DateTime.now();
      
      return result;
    } catch (e) {
      print('Error getting adherence statistics: $e');
      return {
        'totalTaken': 0,
        'totalMissed': 0,
        'totalSkipped': 0,
        'totalScheduled': 0,
        'adherenceRate': 0.0,
        'period': {
          'startDate': startDate,
          'endDate': endDate,
        },
      };
    }
  }

  // Get weekly adherence summary with caching
  Future<List<Map<String, dynamic>>> getWeeklyAdherenceSummary({int weeks = 4}) async {
    try {
      // Always get fresh data to ensure latest actions are reflected
      List<Map<String, dynamic>> weeklySummary = [];
      final now = DateTime.now();
      
      // Load all actions once to avoid multiple calls
      final allActions = await getAllMedicineActions();
      
      for (int i = 0; i < weeks; i++) {
        final weekEndDate = now.subtract(Duration(days: i * 7));
        final weekStartDate = weekEndDate.subtract(const Duration(days: 6));
        
        final startDateStr = DateFormat('yyyy-MM-dd').format(weekStartDate);
        final endDateStr = DateFormat('yyyy-MM-dd').format(weekEndDate);
        
        // Get actions for this week from the pre-loaded actions
        final weekActions = _filterActionsForDateRange(
          allActions, 
          startDateStr, 
          endDateStr
        );
        
        // Group actions by date and medicine
        final actionsByDay = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        // Initialize all dates in the week
        for (int d = 0; d < 7; d++) {
          final date = weekStartDate.add(Duration(days: d));
          final dateStr = DateFormat('yyyy-MM-dd').format(date);
          actionsByDay[dateStr] = {};
        }
        
        // Group actions by date and medicine
        for (var action in weekActions) {
          final date = action['date'] as String;
          final medicineId = normalizeId(action['medicineId'] ?? action['id']);
          
          if (!actionsByDay.containsKey(date)) {
            actionsByDay[date] = {};
          }
          if (!actionsByDay[date]!.containsKey(medicineId)) {
            actionsByDay[date]![medicineId] = [];
          }
          actionsByDay[date]![medicineId]!.add(action);
        }
        
        // Calculate daily statistics
        int weeklyTaken = 0;
        int weeklyMissed = 0;
        int weeklySkipped = 0;
        
        actionsByDay.forEach((date, medicineActions) {
          medicineActions.forEach((medicineId, actions) {
            // Sort actions by time to get the latest status
            actions.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
            final latestAction = actions.first;
            
            switch (latestAction['action']) {
              case 'taken':
                weeklyTaken++;
                break;
              case 'missed':
                weeklyMissed++;
                break;
              case 'skipped':
                weeklySkipped++;
                break;
            }
          });
        });
        
        final weeklyTotal = weeklyTaken + weeklyMissed + weeklySkipped;
        final weeklyAdherenceRate = weeklyTotal > 0 ? (weeklyTaken / weeklyTotal) * 100 : 0.0;
        
        weeklySummary.add({
          'week': i + 1,
          'startDate': startDateStr,
          'endDate': endDateStr,
          'statistics': {
            'totalTaken': weeklyTaken,
            'totalMissed': weeklyMissed,
            'totalSkipped': weeklySkipped,
            'totalScheduled': weeklyTotal,
            'adherenceRate': weeklyAdherenceRate,
          },
          'dailyBreakdown': actionsByDay,
        });
      }
      
      return weeklySummary;
    } catch (e) {
      print('Error getting weekly adherence summary: $e');
      return [];
    }
  }

  // Filter actions by date range (helper for getWeeklyAdherenceSummary and getMonthlyAdherenceSummary)
  List<Map<String, dynamic>> _filterActionsForDateRange(
      List<Map<String, dynamic>> allActions, String startDate, String endDate) {
    try {
      // Parse the date strings to DateTime objects for proper comparison
      final startDateTime = DateFormat('yyyy-MM-dd').parse(startDate);
      final endDateTime = DateFormat('yyyy-MM-dd').parse(endDate);
      
      return allActions.where((action) {
        final actionDateStr = action['date'] as String;
        final actionDateTime = DateFormat('yyyy-MM-dd').parse(actionDateStr);
        return actionDateTime.isAfter(startDateTime.subtract(const Duration(days: 1))) && 
               actionDateTime.isBefore(endDateTime.add(const Duration(days: 1)));
      }).toList();
    } catch (e) {
      print('Error filtering actions for date range: $e');
      return [];
    }
  }

  // Check if cache is valid
  bool _isCacheValid(String key) {
    if (!_cache.containsKey(key) || !_cacheTimestamps.containsKey(key)) {
      return false;
    }
    
    final timestamp = _cacheTimestamps[key]!;
    final now = DateTime.now();
    final difference = now.difference(timestamp).inMinutes;
    
    return difference < _cacheValidityMinutes;
  }

  // Clear all caches
  void clearCache() {
    try {
      _cache.clear();
      _cacheTimestamps.clear();
      print('🧹 MedicineActionService: All caches cleared');
    } catch (e) {
      print('❌ MedicineActionService: Error clearing cache: $e');
    }
  }

  // Check if medicine is taken for a specific date and time
  Future<bool> isMedicineTaken(String medicineId, String date, String time) async {
    try {
      final actions = await getAllMedicineActions();
      final normalizedId = normalizeId(medicineId);
      
      return actions.any((action) =>
          normalizeId(action['medicineId'] ?? action['id']) == normalizedId &&
          action['date'] == date &&
          action['time'] == time &&
          action['action'] == 'taken');
    } catch (e) {
      print('Error checking medicine taken status: $e');
      return false;
    }
  }

  // Get adherence streak (consecutive days of taking medicine)
  Future<int> getAdherenceStreak(String medicineId) async {
    try {
      final today = DateTime.now();
      int streak = 0;
      final normalizedId = normalizeId(medicineId);
      
      for (int i = 0; i < 365; i++) { // Check up to 1 year
        final checkDate = today.subtract(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(checkDate);
        
        final isTaken = await isMedicineTaken(normalizedId, dateStr, 'any');
        
        if (isTaken) {
          streak++;
        } else {
          break; // Streak broken
        }
      }
      
      return streak;
    } catch (e) {
      print('Error getting adherence streak: $e');
      return 0;
    }
  }

  // Clear all stored data
  Future<void> clearAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('medicine_actions');
      await prefs.remove('daily_adherence_summary');
      print('All medicine action data cleared');
    } catch (e) {
      print('Error clearing data: $e');
    }
  }

  // Export data for backup
  Future<Map<String, dynamic>> exportData() async {
    try {
      final actions = await getAllMedicineActions();
      final summary = await getDailyAdherenceSummary();
      
      return {
        'exportInfo': {
          'exportDate': DateTime.now().toIso8601String(),
          'totalActions': actions.length,
        },
        'medicineActions': actions,
        'dailySummary': summary,
      };
    } catch (e) {
      print('Error exporting data: $e');
      return {};
    }
  }

  // Check if a medicine is currently postponed
  Future<bool> isMedicinePostponed(String medicineId, String date) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final normalizedId = normalizeId(medicineId);
      final postponedKey = 'postponed_medicine_${normalizedId}_$date';
      return prefs.containsKey(postponedKey);
    } catch (e) {
      print('Error checking postponed medicine: $e');
      return false;
    }
  }

  // Get all postponed medicines
  Future<List<Map<String, dynamic>>> getPostponedMedicines() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('postponed_medicine_'));
      
      final List<Map<String, dynamic>> postponed = [];
      
      for (var key in keys) {
        final data = prefs.getString(key);
        if (data != null) {
          postponed.add(jsonDecode(data));
        }
      }
      
      return postponed;
    } catch (e) {
      print('Error getting postponed medicines: $e');
      return [];
    }
  }

  // Get monthly adherence summary with caching
  Future<List<Map<String, dynamic>>> getMonthlyAdherenceSummary({int months = 6}) async {
    try {
      // Always get fresh data to ensure latest actions are reflected
      List<Map<String, dynamic>> monthlySummary = [];
      final now = DateTime.now();
      
      // Load all actions once to avoid multiple calls
      final allActions = await getAllMedicineActions();
      
      for (int i = 0; i < months; i++) {
        final monthEndDate = DateTime(now.year, now.month - i, 1).subtract(const Duration(days: 1));
        final monthStartDate = DateTime(now.year, now.month - i, 1);
        
        final startDateStr = DateFormat('yyyy-MM-dd').format(monthStartDate);
        final endDateStr = DateFormat('yyyy-MM-dd').format(monthEndDate);
        
        // Get actions for this month from the pre-loaded actions
        final monthActions = _filterActionsForDateRange(
          allActions,
          startDateStr,
          endDateStr
        );
        
        // Group actions by date and medicine
        final actionsByDay = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        // Initialize all dates in the month
        var currentDate = monthStartDate;
        while (currentDate.isBefore(monthEndDate.add(const Duration(days: 1)))) {
          final dateStr = DateFormat('yyyy-MM-dd').format(currentDate);
          actionsByDay[dateStr] = {};
          currentDate = currentDate.add(const Duration(days: 1));
        }
        
        // Group actions by date and medicine
        for (var action in monthActions) {
          final date = action['date'] as String;
          final medicineId = normalizeId(action['medicineId'] ?? action['id']);
          
          if (!actionsByDay.containsKey(date)) {
            actionsByDay[date] = {};
          }
          if (!actionsByDay[date]!.containsKey(medicineId)) {
            actionsByDay[date]![medicineId] = [];
          }
          actionsByDay[date]![medicineId]!.add(action);
        }
        
        // Calculate monthly statistics
        int monthlyTaken = 0;
        int monthlyMissed = 0;
        int monthlySkipped = 0;
        
        actionsByDay.forEach((date, medicineActions) {
          medicineActions.forEach((medicineId, actions) {
            // Sort actions by time to get the latest status
            actions.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
            final latestAction = actions.first;
            
            switch (latestAction['action']) {
              case 'taken':
                monthlyTaken++;
                break;
              case 'missed':
                monthlyMissed++;
                break;
              case 'skipped':
                monthlySkipped++;
                break;
            }
          });
        });
        
        final monthlyTotal = monthlyTaken + monthlyMissed + monthlySkipped;
        final monthlyAdherenceRate = monthlyTotal > 0 ? (monthlyTaken / monthlyTotal) * 100 : 0.0;
        
        monthlySummary.add({
          'month': DateFormat('MMMM yyyy').format(monthStartDate),
          'startDate': startDateStr,
          'endDate': endDateStr,
          'statistics': {
            'totalTaken': monthlyTaken,
            'totalMissed': monthlyMissed,
            'totalSkipped': monthlySkipped,
            'totalScheduled': monthlyTotal,
            'adherenceRate': monthlyAdherenceRate,
          },
          'dailyBreakdown': actionsByDay,
        });
      }
      
      return monthlySummary;
    } catch (e) {
      print('Error getting monthly adherence summary: $e');
      return [];
    }
  }

  // Clear test data and prepare for real app action service data
  Future<bool> clearTestDataAndPrepareProdData() async {
    try {
      print('🧹 MedicineActionService: Clearing test data and preparing for real app action data');
      final prefs = await SharedPreferences.getInstance();
      
      // Step 1: Backup current data
      final currentActions = prefs.getString('medicine_actions');
      if (currentActions != null && currentActions.isNotEmpty) {
        await prefs.setString('medicine_actions_backup_before_clear', currentActions);
        print('💾 MedicineActionService: Backed up current actions data');
      }
      
      final currentSummary = prefs.getString('daily_adherence_summary');
      if (currentSummary != null && currentSummary.isNotEmpty) {
        await prefs.setString('daily_adherence_summary_backup_before_clear', currentSummary);
        print('💾 MedicineActionService: Backed up current summary data');
      }
      
      // Step 2: Clear all existing data
      await prefs.remove('medicine_actions');
      await prefs.remove('daily_adherence_summary');
      
      // Step 3: Clear postponed medicines
      final allKeys = prefs.getKeys().toList();
      for (final key in allKeys) {
        if (key.startsWith('postponed_medicine_')) {
          await prefs.remove(key);
        }
      }
      
      // Step 4: Clear cache
      clearCache();
      
      print('✅ MedicineActionService: Successfully cleared test data. System is ready for real app action data.');
      
      // Step 5: Notify UI to refresh
      _notifyUIUpdate();
      
      return true;
    } catch (e) {
      print('❌ MedicineActionService: Error clearing test data: $e');
      return false;
    }
  }

  // Restore test data if needed (for development purposes)
  Future<bool> restoreBackupBeforeClear() async {
    try {
      print('🔄 MedicineActionService: Attempting to restore data from backup');
      final prefs = await SharedPreferences.getInstance();
      
      bool restored = false;
      
      // Restore actions
      final backupActions = prefs.getString('medicine_actions_backup_before_clear');
      if (backupActions != null && backupActions.isNotEmpty) {
        await prefs.setString('medicine_actions', backupActions);
        print('✅ MedicineActionService: Restored actions from backup');
        restored = true;
      }
      
      // Restore summary
      final backupSummary = prefs.getString('daily_adherence_summary_backup_before_clear');
      if (backupSummary != null && backupSummary.isNotEmpty) {
        await prefs.setString('daily_adherence_summary', backupSummary);
        print('✅ MedicineActionService: Restored summary from backup');
        restored = true;
      }
      
      // Clear cache
      clearCache();
      
      // Notify UI to refresh
      if (restored) {
        _notifyUIUpdate();
      }
      
      return restored;
    } catch (e) {
      print('❌ MedicineActionService: Error restoring data from backup: $e');
      return false;
    }
  }
  
  // Import real app actions data from native side
  Future<bool> importRealAppActionsData() async {
    try {
      print('📥 MedicineActionService: Importing real app actions data');
      
      // Fetch data from native side
      final result = await _channel.invokeMethod('getRealAppActionsData');
      if (result == null || (result is String && result.isEmpty)) {
        print('⚠️ MedicineActionService: No data received from native side');
        return false;
      }
      
      // Parse and validate the data
      try {
        final dataMap = jsonDecode(result as String);
        if (dataMap is! Map) return false;
        
        // Process all actions at once
        if (dataMap.containsKey('actions') && dataMap['actions'] is List) {
          final actions = dataMap['actions'] as List;
          print('📊 MedicineActionService: Processing ${actions.length} actions');
          
          // Process each action
          int processed = 0;
          for (final action in actions) {
            if (action is Map<String, dynamic>) {
              // Use the action's own type or default to 'unknown'
              final actionType = _normalizeActionType(action['action']?.toString());
              await _handleMedicineAction(action, actionType);
              processed++;
            }
          }
          
          print('✅ MedicineActionService: Imported $processed actions');
          return processed > 0;
        }
    } catch (e) {
        print('❌ MedicineActionService: Error parsing imported data: $e');
      }
      
      return false;
    } catch (e) {
      print('❌ MedicineActionService: Error importing data: $e');
      return false;
    }
  }

  // Method to notify UI of changes with enhanced reliability and safety
  void _notifyUIUpdate() {
    print('📱 MedicineActionService: Notifying UI update');
    
    // Add debouncing to prevent multiple rapid calls
    final now = DateTime.now();
    
    if (_lastNotificationTime != null) {
      final timeSinceLastNotification = now.difference(_lastNotificationTime!).inMilliseconds;
      if (timeSinceLastNotification < 500) { // 500ms debounce
        print('⏱️ MedicineActionService: Debouncing notification (${timeSinceLastNotification}ms since last)');
        return;
      }
    }
    
    _lastNotificationTime = now;
    
    // Clear all caches to ensure fresh data
    clearCache();
    
    // Step 1: Try callback notification
    if (onMedicineActionReceived != null) {
      try {
        onMedicineActionReceived!({
          'type': 'refresh',
          'timestamp': now.toIso8601String()
        });
        print('✅ MedicineActionService: Notified via callback');
      } catch (e) {
        print('⚠️ MedicineActionService: Error in callback notification: $e');
      }
    }
    
    // Step 2: Try global key update
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final state = AdherenceTrackingScreen.globalKey.currentState;
        if (state != null && !state.isDisposed() && state.mounted) {
          state.safeLoadData();
          print('✅ MedicineActionService: Updated via global key');
        }
    } catch (e) {
        print('⚠️ MedicineActionService: Error updating via global key: $e');
    }
    });
  }

  // Create a helper method to access the screen from anywhere
  Future<void> refreshAdherenceTrackingScreen() async {
    try {
      print('🔄 Helper: Refreshing adherence tracking screen');
      final state = AdherenceTrackingScreen.globalKey.currentState;
      
      if (state != null && !state.isDisposed() && state.mounted) {
        state.safeLoadData();
      }
    } catch (e) {
      print('⚠️ Helper: Error refreshing screen: $e');
    }
  }

  // Helper method to safely convert Map<dynamic, dynamic> to Map<String, dynamic>
  Map<String, dynamic> _safeMapConversion(Map inputMap) {
    final result = <String, dynamic>{};
    
    inputMap.forEach((key, value) {
      if (key is String) {
        if (value is Map) {
          // Recursively convert nested maps
          result[key] = _safeMapConversion(value);
        } else if (value is List) {
          // Handle lists that might contain maps
          final convertedList = value.map((item) {
            if (item is Map) {
              return _safeMapConversion(item);
            }
            return item;
          }).toList();
          result[key] = convertedList;
        } else {
          // Directly use primitives
          result[key] = value;
        }
      }
    });
    
    return result;
  }
  
  // Helper method to safely parse JSON to Map<String, dynamic>
  Map<String, dynamic> _safelyParseJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map) {
        return _safeMapConversion(decoded);
      }
    } catch (e) {
      print('⚠️ MedicineActionService: Error parsing JSON: $e');
    }
    return {};
  }
} 