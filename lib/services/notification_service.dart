import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';

// Data class for notification queue items
class NotificationData {
  final int notificationId;
  final String title;
  final String body;
  final Map<String, dynamic> payload;
  final DateTime scheduledTime;
  final String type; // 'medicine', 'reminder', 'alert', etc.
  final int priority; // 1 = high, 2 = medium, 3 = low

  NotificationData({
    required this.notificationId,
    required this.title,
    required this.body,
    required this.payload,
    required this.scheduledTime,
    required this.type,
    this.priority = 2,
  });

  Map<String, dynamic> toJson() => {
    'notificationId': notificationId,
    'title': title,
    'body': body,
    'payload': payload,
    'scheduledTime': scheduledTime.toIso8601String(),
    'type': type,
    'priority': priority,
  };

  factory NotificationData.fromJson(Map<String, dynamic> json) => NotificationData(
    notificationId: json['notificationId'],
    title: json['title'],
    body: json['body'],
    payload: json['payload'],
    scheduledTime: DateTime.parse(json['scheduledTime']),
    type: json['type'],
    priority: json['priority'] ?? 2,
  );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const platform = MethodChannel('notification_service');
  bool _isInitialized = false;

  // Track active alarms to prevent duplicates - using Set for unique IDs
  static final Set<int> _activeAlarms = <int>{};
  static final Map<int, Timer> _activeTimers = <int, Timer>{};
  
  // Track last scheduled medicine data to prevent unnecessary rescheduling
  static String _lastScheduledMedicineDataHash = '';
  static DateTime _lastSchedulingTime = DateTime(1970);
  static List<Map<String, dynamic>> _lastScheduledMedicines = [];
  
  // Global flag to prevent concurrent scheduling
  static bool _isSchedulingInProgress = false;
  
  // NEW: Notification queue system
  static final List<NotificationData> _notificationQueue = <NotificationData>[];
  static bool _isNotificationActive = false;
  static int _currentNotificationId = -1;
  static Timer? _queueProcessorTimer;
  
  // Static key definitions matching the native service
  static const String fullScreenKey = 'fullScreen';
  static const String vibrationKey = 'vibration';
  static const String soundKey = 'sound';
  static const String useDefaultAlarmKey = 'useDefaultAlarm';
  static const String customSoundPathKey = 'customSoundPath';
  static const String voiceFilePathKey = 'voiceFilePath';
  static const String snoozeDurationKey = 'snoozeDuration';

  // NEW: Notification queue constants
  static const String _notificationQueueKey = 'notification_queue';
  static const Duration _queueProcessingDelay = Duration(seconds: 2);
  static const int _maxQueueSize = 50; // Prevent memory issues
  
  /// Initialize the notification service and clear all existing alarms
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // CRITICAL: Get snoozed alarm IDs before clearing all alarms
      final prefs = await SharedPreferences.getInstance();
      final snoozeKeys = prefs.getKeys().where((key) => key.startsWith('snoozed_alarm_')).toList();
      Set<int> snoozedAlarmIds = {};
      
      // Collect all snoozed alarm IDs to preserve them
      for (var key in snoozeKeys) {
        try {
          final snoozeDataString = prefs.getString(key) ?? '{}';
          if (snoozeDataString.isNotEmpty) {
            final snoozeData = jsonDecode(snoozeDataString);
            
            // Check both alarmId and snoozeAlarmId fields
            if (snoozeData.containsKey('alarmId')) {
              final alarmId = snoozeData['alarmId'];
              if (alarmId != null) {
                snoozedAlarmIds.add(alarmId is int ? alarmId : int.tryParse(alarmId.toString()) ?? 0);
              }
            }
            
            // Also check original ID + 100000 pattern (used in native code)
            if (snoozeData.containsKey('id') || snoozeData.containsKey('originalAlarmId')) {
              final originalId = snoozeData['id'] ?? snoozeData['originalAlarmId'];
              if (originalId != null) {
                final origIntId = originalId is int ? originalId : int.tryParse(originalId.toString()) ?? 0;
                final snoozeAlarmId = origIntId + 100000; // This matches the native snooze ID generation
                snoozedAlarmIds.add(snoozeAlarmId);
              }
            }
          }
        } catch (e) {
          print('Error reading snooze data during initialization: $e');
        }
      }
      
      print("🔍 Found ${snoozedAlarmIds.length} snoozed alarm IDs to preserve during initialization: $snoozedAlarmIds");
      
      // Clear ALL existing alarms and notifications immediately
      await _cancelAllEffectTriggers();
      _activeAlarms.clear();
      
      // Cancel any active timers
      for (var timer in _activeTimers.values) {
        timer.cancel();
      }
      _activeTimers.clear();
      
      // NEW: Initialize notification queue
      await _initializeNotificationQueue();
      
      // Register method channel handler
      if (!_methodHandlerRegistered) {
        platform.setMethodCallHandler(_handleMethodCall);
        _methodHandlerRegistered = true;
        print("📱 Method channel handler registered during initialization");
      }
      
      _isInitialized = true;
      print("✅ Native notification service initialized successfully");
      print("🔔 Snoozed alarms preserved during initialization: ${snoozedAlarmIds.length}");
      
      // Restore snoozed alarms after initialization
      await _restoreSnoozedAlarms();
    } catch (e) {
      print('❌ Error initializing notification service: $e');
      throw e;
    }
  }

  /// Restore snoozed alarms after initialization
  Future<void> _restoreSnoozedAlarms() async {
    try {
      print('🔄 Restoring snoozed alarms after initialization...');
      
      final prefs = await SharedPreferences.getInstance();
      final snoozeKeys = prefs.getKeys().where((key) => key.startsWith('snoozed_alarm_')).toList();
      
      if (snoozeKeys.isEmpty) {
        print('ℹ️ No snoozed alarms to restore');
        return;
      }
      
      int restoredCount = 0;
      int expiredCount = 0;
      
      for (var key in snoozeKeys) {
        try {
          final snoozeDataString = prefs.getString(key);
          if (snoozeDataString != null && snoozeDataString.isNotEmpty) {
            final snoozeData = jsonDecode(snoozeDataString);
            
            // Parse snooze time
            DateTime? snoozeTime;
            if (snoozeData.containsKey('snoozeTime')) {
              if (snoozeData['snoozeTime'] is int) {
                snoozeTime = DateTime.fromMillisecondsSinceEpoch(snoozeData['snoozeTime']);
              } else {
                snoozeTime = DateTime.tryParse(snoozeData['snoozeTime'].toString());
              }
            }
            
            if (snoozeTime != null && snoozeTime.isAfter(DateTime.now())) {
                          // Restore the snoozed alarm
            final enhancedData = {
              ...Map<String, dynamic>.from(snoozeData),
              'isSnooze': true,
              'snoozeTime': snoozeTime.toIso8601String(),
            };
              
              await scheduleSingleMedicationReminder(enhancedData);
              restoredCount++;
              print('✅ Restored snoozed alarm: ${snoozeData['medicineName'] ?? 'Medicine'} at $snoozeTime');
            } else {
              // Remove expired snoozed alarm
              await prefs.remove(key);
              expiredCount++;
              print('🗑️ Removed expired snoozed alarm: $key');
            }
          }
        } catch (e) {
          print('❌ Error restoring snoozed alarm $key: $e');
          // Remove corrupted data
          await prefs.remove(key);
        }
      }
      
      print('✅ Restored $restoredCount snoozed alarms, removed $expiredCount expired alarms');
    } catch (e) {
      print('❌ Error restoring snoozed alarms: $e');
    }
  }

  /// NEW: Initialize notification queue from persistent storage
  Future<void> _initializeNotificationQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = prefs.getString(_notificationQueueKey);
      
      if (queueJson != null && queueJson.isNotEmpty) {
        final List<dynamic> queueList = jsonDecode(queueJson);
        _notificationQueue.clear();
        
        for (final item in queueList) {
          try {
            final notificationData = NotificationData.fromJson(item);
            // Only add notifications that haven't expired (older than 1 hour)
            if (DateTime.now().difference(notificationData.scheduledTime).inHours < 1) {
              _notificationQueue.add(notificationData);
            }
          } catch (e) {
            print('⚠️ Error parsing notification data: $e');
          }
        }
        
        print('📋 Loaded ${_notificationQueue.length} notifications from queue');
        
        // Start processing queue if there are items
        if (_notificationQueue.isNotEmpty) {
          _startQueueProcessing();
        }
      }
    } catch (e) {
      print('❌ Error initializing notification queue: $e');
    }
  }

  /// NEW: Save notification queue to persistent storage
  Future<void> _saveNotificationQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = jsonEncode(_notificationQueue.map((item) => item.toJson()).toList());
      await prefs.setString(_notificationQueueKey, queueJson);
      print('💾 Saved ${_notificationQueue.length} notifications to queue');
    } catch (e) {
      print('❌ Error saving notification queue: $e');
    }
  }

  /// NEW: Add notification to queue
  Future<void> addToNotificationQueue(NotificationData notification) async {
    try {
      // Prevent queue overflow
      if (_notificationQueue.length >= _maxQueueSize) {
        print('⚠️ Notification queue full, removing oldest item');
        _notificationQueue.removeAt(0);
      }
      
      // Add to queue and sort by priority and time
      _notificationQueue.add(notification);
      _notificationQueue.sort((a, b) {
        // First sort by priority (1 = high, 2 = medium, 3 = low)
        if (a.priority != b.priority) {
          return a.priority.compareTo(b.priority);
        }
        // Then sort by scheduled time
        return a.scheduledTime.compareTo(b.scheduledTime);
      });
      
      await _saveNotificationQueue();
      
      print('📋 Added notification to queue: ${notification.title} (Priority: ${notification.priority})');
      print('📊 Queue size: ${_notificationQueue.length}');
      
      // Start processing if no notification is currently active
      if (!_isNotificationActive) {
        _startQueueProcessing();
      }
    } catch (e) {
      print('❌ Error adding notification to queue: $e');
    }
  }

  /// NEW: Start processing the notification queue
  void _startQueueProcessing() {
    if (_queueProcessorTimer != null) {
      _queueProcessorTimer!.cancel();
    }
    
    _queueProcessorTimer = Timer(_queueProcessingDelay, () {
      _processNextNotification();
    });
    
    print('🔄 Started notification queue processing');
  }

  /// NEW: Process the next notification in the queue
  Future<void> _processNextNotification() async {
    if (_notificationQueue.isEmpty) {
      _isNotificationActive = false;
      _currentNotificationId = -1;
      print('📋 Notification queue is empty');
      return;
    }
    
    if (_isNotificationActive) {
      print('⚠️ Notification already active, skipping queue processing');
      return;
    }
    
    final notification = _notificationQueue.removeAt(0);
    _isNotificationActive = true;
    _currentNotificationId = notification.notificationId;
    
    print('📱 Processing notification: ${notification.title} (ID: ${notification.notificationId})');
    
    try {
      // Show the notification
      await _showNotification(notification);
      
      // Schedule next notification processing
      Timer(_queueProcessingDelay, () {
        _isNotificationActive = false;
        _currentNotificationId = -1;
        _processNextNotification();
      });
      
    } catch (e) {
      print('❌ Error processing notification: $e');
      _isNotificationActive = false;
      _currentNotificationId = -1;
      
      // Try next notification
      Timer(_queueProcessingDelay, () {
        _processNextNotification();
      });
    }
  }

  /// NEW: Show a notification (can be overridden for different notification types)
  Future<void> _showNotification(NotificationData notification) async {
    try {
      // Use native notification service
      await platform.invokeMethod('showNotification', {
        'notificationId': notification.notificationId,
        'title': notification.title,
        'body': notification.body,
        'payload': jsonEncode(notification.payload),
        'type': notification.type,
        'priority': notification.priority,
      });
      
      print('✅ Notification shown: ${notification.title}');
    } catch (e) {
      print('❌ Error showing notification: $e');
      rethrow;
    }
  }

  /// NEW: Get notification queue status (separate from alarm queue)
  Map<String, dynamic> getNotificationQueueStatus() {
    return {
      'queueSize': _notificationQueue.length,
      'isNotificationActive': _isNotificationActive,
      'currentNotificationId': _currentNotificationId,
      'queueItems': _notificationQueue.map((item) => {
        'id': item.notificationId,
        'title': item.title,
        'type': item.type,
        'priority': item.priority,
        'scheduledTime': item.scheduledTime.toIso8601String(),
      }).toList(),
    };
  }

  /// NEW: Clear notification queue
  Future<void> clearNotificationQueue() async {
    try {
      _notificationQueue.clear();
      _isNotificationActive = false;
      _currentNotificationId = -1;
      
      if (_queueProcessorTimer != null) {
        _queueProcessorTimer!.cancel();
        _queueProcessorTimer = null;
      }
      
      await _saveNotificationQueue();
      print('🧹 Notification queue cleared');
    } catch (e) {
      print('❌ Error clearing notification queue: $e');
    }
  }

  /// NEW: Remove specific notification from queue
  Future<void> removeFromNotificationQueue(int notificationId) async {
    try {
      final initialLength = _notificationQueue.length;
      _notificationQueue.removeWhere((item) => item.notificationId == notificationId);
      final finalLength = _notificationQueue.length;
      
      if (finalLength < initialLength) {
        await _saveNotificationQueue();
        print('🗑️ Removed notification $notificationId from queue');
      }
    } catch (e) {
      print('❌ Error removing notification from queue: $e');
    }
  }

  /// NEW: Convenience method to add medicine notification to queue
  Future<void> queueMedicineNotification({
    required int notificationId,
    required String medicineName,
    required String dosage,
    required DateTime scheduledTime,
    required Map<String, dynamic> payload,
    int priority = 1, // High priority for medicine notifications
  }) async {
    final notification = NotificationData(
      notificationId: notificationId,
      title: 'Medicine Reminder',
      body: 'Time to take $medicineName $dosage',
      payload: payload,
      scheduledTime: scheduledTime,
      type: 'medicine',
      priority: priority,
    );
    
    await addToNotificationQueue(notification);
  }

  /// NEW: Convenience method to add general notification to queue
  Future<void> queueGeneralNotification({
    required int notificationId,
    required String title,
    required String body,
    required Map<String, dynamic> payload,
    required DateTime scheduledTime,
    String type = 'general',
    int priority = 2,
  }) async {
    final notification = NotificationData(
      notificationId: notificationId,
      title: title,
      body: body,
      payload: payload,
      scheduledTime: scheduledTime,
      type: type,
      priority: priority,
    );
    
    await addToNotificationQueue(notification);
  }

  /// Check if overlay permission is granted
  Future<bool> isOverlayPermissionGranted() async {
    try {
      // Use ONLY the native method - most reliable
      final result = await platform.invokeMethod<bool>('checkOverlayPermissionDirect');
      print("🔐 Native overlay permission status: $result");
      return result ?? false;
    } catch (e) {
      print('❌ Error checking overlay permission: $e');
      return false;
    }
  }

  /// Generate a hash for medicine data to detect changes
  String _generateMedicineDataHash(List<Map<String, dynamic>> medicines) {
    final medicineData = medicines.map((medicine) => {
      'id': medicine['id'],
      'name': medicine['name'],
      'time': medicine['time'],
      'dosage': medicine['dosage'],
      'frequency': medicine['frequency'],
      'startDate': medicine['startDate'],
      'endDate': medicine['endDate'],
      'scheduleDate': medicine['scheduleDate'], // Include schedule date in hash
    }).toList();
    
    return medicineData.toString().hashCode.toString();
  }


  /// Force reschedule medication reminders (bypasses change detection)
  Future<void> forceScheduleMedicationReminders(List<Map<String, dynamic>> medicines) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    print("🔄 Force rescheduling medication reminders");
    _lastScheduledMedicineDataHash = ''; // Reset hash to force rescheduling
    _lastScheduledMedicines.clear(); // Clear stored medicines
    await scheduleMedicationReminders(medicines);
  }

  /// Main method to schedule medication reminders using only native AlarmManager
  Future<void> scheduleMedicationReminders(List<Map<String, dynamic>> medicines) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Prevent concurrent scheduling
    if (_isSchedulingInProgress) {
      print("⏭️ Skipping alarm rescheduling - scheduling already in progress");
      return;
    }
    
    // Check if medicine data has actually changed
    final currentHash = _generateMedicineDataHash(medicines);
    final now = DateTime.now();
    final timeSinceLastScheduling = now.difference(_lastSchedulingTime);
    
    // Check if this is a date change (different scheduleDate in medicines)
    bool isDateChange = false;
    if (_lastScheduledMedicines.isNotEmpty && medicines.isNotEmpty) {
      try {
        final previousScheduleDate = _lastScheduledMedicines.first['scheduleDate']?.toString() ?? '';
        final currentScheduleDate = medicines.first['scheduleDate']?.toString() ?? '';
        isDateChange = previousScheduleDate != currentScheduleDate;
        if (isDateChange) {
          print('📅 Date change detected: $previousScheduleDate -> $currentScheduleDate');
        }
      } catch (e) {
        print('⚠️ Error comparing schedule dates: $e');
      }
    }
    
    // Skip rescheduling if:
    // 1. Medicine data hasn't changed (same hash)
    // 2. Less than 60 seconds since last scheduling (increased threshold to prevent loops)
    // 3. Not a date change
    if (currentHash == _lastScheduledMedicineDataHash && 
        timeSinceLastScheduling.inSeconds < 60 && 
        !isDateChange) {
      print("⏭️ Skipping alarm rescheduling - no changes detected and recent scheduling");
      return;
    }
    
    if (isDateChange) {
      print("📅 Date change detected - proceeding with alarm rescheduling");
    }
    
    print("🔄 Medicine data changed or sufficient time passed - proceeding with alarm scheduling");
    _isSchedulingInProgress = true;
    _lastScheduledMedicineDataHash = currentHash;
    _lastSchedulingTime = now;
    _lastScheduledMedicines = List.from(medicines); // Store current medicines for comparison
    
    try {
      // STEP 1: Cancel ONLY regular alarms, preserve snoozed ones
      print("🧹 Clearing regular alarms (preserving snoozed)...");
      
      // Get list of snoozed alarm IDs to preserve
      final prefs = await SharedPreferences.getInstance();
      final snoozeKeys = prefs.getKeys().where((key) => key.startsWith('snoozed_alarm_')).toList();
      Set<int> snoozedAlarmIds = {};
      
      // First collect all snoozed alarm IDs properly
      for (var key in snoozeKeys) {
        try {
          final snoozeDataString = prefs.getString(key) ?? '{}';
          if (snoozeDataString.isNotEmpty) {
            final snoozeData = jsonDecode(snoozeDataString);
            
            // Check both alarmId and snoozeAlarmId fields
            if (snoozeData.containsKey('alarmId')) {
              final alarmId = snoozeData['alarmId'];
              if (alarmId != null) {
                snoozedAlarmIds.add(alarmId is int ? alarmId : int.tryParse(alarmId.toString()) ?? 0);
              }
            }
            
            // Also check original ID + 100000 pattern (used in native code)
            if (snoozeData.containsKey('id') || snoozeData.containsKey('originalAlarmId')) {
              final originalId = snoozeData['id'] ?? snoozeData['originalAlarmId'];
              if (originalId != null) {
                final origIntId = originalId is int ? originalId : int.tryParse(originalId.toString()) ?? 0;
                final snoozeAlarmId = origIntId + 100000; // This matches the native snooze ID generation
                snoozedAlarmIds.add(snoozeAlarmId);
              }
            }
          }
        } catch (e) {
          print('Error reading snooze data: $e');
        }
      }
      
      print("🔍 Found ${snoozedAlarmIds.length} snoozed alarm IDs to preserve: $snoozedAlarmIds");
      
      // Get set of regular alarm IDs to avoid canceling snoozed ones
      Set<int> regularAlarmIds = {};
      for (var medicine in medicines) {
        final medicineId = medicine['id'];
        if (medicineId != null) {
          final times = medicine['time'].toString().split(',');
          for (var timeStr in times) {
            final scheduledTime = _parseTimeString(timeStr.trim());
            if (scheduledTime != null) {
              final alarmId = _generateUniqueAlarmId(medicineId, scheduledTime);
              regularAlarmIds.add(alarmId);
            }
          }
        }
      }
      
      // Only cancel alarms that are NOT snoozed AND are no longer in the regular medicines list
      final alarmsToCancel = Set<int>.from(_activeAlarms)
        ..removeAll(snoozedAlarmIds)
        ..removeAll(regularAlarmIds);
      
      print("🧹 Cancelling ${alarmsToCancel.length} alarms that are neither snoozed nor regular");
      
      // Cancel only those specific alarms
      for (var alarmId in alarmsToCancel) {
        await cancelAlarm(alarmId);
      }
      
      // Update active alarms list to reflect current state
      _activeAlarms.removeAll(alarmsToCancel);
      
      // Cancel timers for removed alarms
      _activeTimers.removeWhere((alarmId, timer) {
        if (alarmsToCancel.contains(alarmId)) {
          timer.cancel();
          return true;
        }
        return false;
      });

      // STEP 2: Schedule new regular reminders (skip if already active)
      print("📅 Scheduling regular medicine reminders...");
      
      int newAlarmsScheduled = 0;
      for (var medicine in medicines) {
        final times = medicine['time'].toString().split(',');
        for (var timeStr in times) {
          final scheduledTime = _parseTimeString(timeStr.trim());
          if (scheduledTime != null) {
            final alarmId = _generateUniqueAlarmId(medicine['id'], scheduledTime);
            
            // Only schedule if not already active (prevents disturbing snoozed alarms)
            if (!_activeAlarms.contains(alarmId)) {
              await _scheduleNativeReminder(medicine, scheduledTime);
              newAlarmsScheduled++;
            }
          }
        }
      }
      
      print("✅ ${newAlarmsScheduled} new regular reminders scheduled. Active alarms: ${_activeAlarms.length}");
      print("🔔 Snoozed alarms preserved: ${snoozedAlarmIds.length}");
      
    } catch (e) {
      print('❌ Error scheduling native reminders: $e');
      rethrow;
    } finally {
      // Always reset the scheduling flag
      _isSchedulingInProgress = false;
    }
  }

  /// Schedule a single medication reminder (for snoozed alarms)
  Future<void> scheduleSingleMedicationReminder(Map<String, dynamic> medicineData) async {
    try {
      final medicineName = medicineData['medicineName'] ?? 'Medicine';
      
      // For snoozed alarms, we must use the snoozeTime, not fall back to scheduledTime
      final isSnooze = medicineData['isSnooze'] ?? false;
      DateTime snoozeTime;
      
      if (isSnooze) {
        // For snoozed alarms, snoozeTime is mandatory
        if (medicineData['snoozeTime'] == null) {
          throw Exception('Snooze time is required for snoozed alarms');
        }
        snoozeTime = DateTime.parse(medicineData['snoozeTime']);
        print('⏰ Using snooze time: $snoozeTime');
      } else {
        // For regular alarms, use scheduledTime
        snoozeTime = DateTime.parse(medicineData['scheduledTime']);
        print('⏰ Using scheduled time: $snoozeTime');
      }
      
      // Generate unique notification ID for snoozed alarm
      final originalId = medicineData['id'] ?? medicineData['snoozeId'];
      final notificationId = isSnooze 
        ? (originalId.hashCode.abs() + snoozeTime.millisecondsSinceEpoch.hashCode.abs()) % 2147483647
        : originalId.hashCode.abs() % 2147483647;
      
      print('📱 Scheduling ${isSnooze ? 'snoozed' : 'regular'} reminder for $medicineName at $snoozeTime');
      print('📱 Using notification ID: $notificationId');
      
      // Fetch current notification settings
      final settings = await getNotificationSettings();
      
      // Prepare payload with all necessary data for native service
      final payload = {
        'id': originalId,
        'alarmId': notificationId,
        'medicineName': medicineName,
        'dosage': medicineData['dosage'] ?? '',
        'timing': medicineData['timing'] ?? '',
        'instructions': medicineData['instructions'] ?? '',
        'foodInstructions': medicineData['foodInstructions'] ?? '',
        'scheduled_time': DateFormat('hh:mm a').format(snoozeTime),
        'trigger_time': snoozeTime.toIso8601String(),
        'isSnooze': isSnooze,
        'snoozeCount': medicineData['snoozeCount'] ?? 0,
        'originalTime': medicineData['originalTime'],
        'frontImagePath': medicineData['frontImagePath'],
        'backImagePath': medicineData['backImagePath'],
        'settings': {
          'fullScreen': settings['fullScreen'] ?? true,
          'vibration': settings['vibration'] ?? true,
          'sound': settings['sound'] ?? true,
          'useDefaultAlarm': settings['useDefaultAlarm'] ?? true,
          'customSoundPath': settings['customSoundPath'] ?? '',
          'voiceFilePath': medicineData['voiceFilePath'] ?? '',
        },
      };
      
      // Debug: Log image paths and voice path being sent to native
      print('🖼️ Notification payload paths:');
      print('  - Front image path: ${medicineData['frontImagePath'] ?? 'null'}');
      print('  - Back image path: ${medicineData['backImagePath'] ?? 'null'}');
      print('  - Voice file path: ${medicineData['voiceFilePath'] ?? 'null'}');
      print('  - Full payload: ${jsonEncode(payload)}');
      
      // Schedule the alarm using native AlarmManager
      await platform.invokeMethod('scheduleEffectTrigger', {
        'alarmId': notificationId,
        'triggerTime': snoozeTime.millisecondsSinceEpoch,
        'payload': jsonEncode(payload),
      });
      
      // Track this alarm as active
      _activeAlarms.add(notificationId);
      
      // For snoozed alarms, also save the current state to ensure persistence
      if (isSnooze) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final snoozeAlarmId = notificationId;
          final snoozeData = {
            ...Map<String, dynamic>.from(medicineData),
            'snoozeTime': snoozeTime.toIso8601String(),
            'isSnooze': true,
            'snoozeAlarmId': snoozeAlarmId,
          };
          await prefs.setString('snoozed_alarm_$snoozeAlarmId', jsonEncode(snoozeData));
          print('💾 Saved snoozed alarm state for persistence: $snoozeAlarmId');
        } catch (e) {
          print('❌ Error saving snoozed alarm state: $e');
        }
      }
      
      print('✅ Successfully scheduled ${isSnooze ? 'snoozed' : 'regular'} notification ID: $notificationId');
      
    } catch (e) {
      print('❌ Error scheduling single medication reminder: $e');
      throw e;
    }
  }

  /// Schedule a single native reminder with proper deduplication
  Future<void> _scheduleNativeReminder(Map<String, dynamic> medicine, DateTime scheduledTime) async {
    try {
      final now = DateTime.now();
      
      // Get the target time for today
      var triggerTime = DateTime(
        now.year,
        now.month,
        now.day,
        scheduledTime.hour,
        scheduledTime.minute,
      );

      // If time has passed for today, schedule for tomorrow
      if (triggerTime.isBefore(now)) {
        triggerTime = DateTime(
          now.year,
          now.month,
          now.day + 1,
          scheduledTime.hour,
          scheduledTime.minute,
        );
      }

      // Generate unique alarm ID based on medicine ID and time
      final alarmId = _generateUniqueAlarmId(medicine['id'], scheduledTime);
      
      // Check if this alarm is already scheduled
      if (_activeAlarms.contains(alarmId)) {
        print("⚠️ Native alarm $alarmId already scheduled, skipping duplicate");
        return;
      }

      // Fetch current notification settings
      final settings = await getNotificationSettings();

      // Prepare payload with all necessary data for native service
      final payload = {
        'id': medicine['id'],
        'alarmId': alarmId,
        'medicineName': medicine['name'] ?? 'Medicine',
        'dosage': medicine['dosage'] ?? '',
        'timing': medicine['timing'] ?? '',
        'instructions': medicine['instructions'] ?? '',
        'foodInstructions': medicine['foodInstructions'] ?? '',
        'scheduled_time': DateFormat('hh:mm a').format(scheduledTime),
        'trigger_time': triggerTime.toIso8601String(),
        'frontImagePath': medicine['frontImagePath'],
        'backImagePath': medicine['backImagePath'],
        'settings': {
          fullScreenKey: settings['fullScreen'] ?? true,
          vibrationKey: settings['vibration'] ?? true,
          soundKey: settings['sound'] ?? true,
          useDefaultAlarmKey: settings['useDefaultAlarm'] ?? true,
          customSoundPathKey: settings['customSoundPath'] ?? '',
          voiceFilePathKey: medicine['voiceFilePath'] ?? '',
        },
      };

      // Schedule the alarm using native AlarmManager only
      await platform.invokeMethod('scheduleEffectTrigger', {
        'alarmId': alarmId,
        'triggerTime': triggerTime.millisecondsSinceEpoch,
        'payload': json.encode(payload),
      });

      // Track this alarm as active
      _activeAlarms.add(alarmId);

      print("✅ Scheduled native alarm $alarmId for ${medicine['name']} at ${DateFormat('yyyy-MM-dd HH:mm').format(triggerTime)}");

    } catch (e) {
      print('❌ Error scheduling native reminder: $e');
      rethrow;
    }
  }

  /// Generate a unique alarm ID to prevent collisions
  int _generateUniqueAlarmId(dynamic medicineId, DateTime scheduledTime) {
    // Combine medicine ID with hour/minute to create unique ID
    final baseId = (medicineId?.hashCode ?? 0) & 0xFFFF; // 16 bits for medicine
    final timeId = (scheduledTime.hour * 60 + scheduledTime.minute) & 0xFFFF; // 16 bits for time
    return (baseId << 16) | timeId; // 32-bit unique ID
  }

  /// Parse time string to DateTime
  DateTime? _parseTimeString(String timeStr) {
    try {
      // Handle various time formats
      timeStr = timeStr.trim();
      
      // Try 12-hour format first (e.g., "2:30 PM")
      try {
        return DateFormat('h:mm a').parse(timeStr);
      } catch (e) {
        // Try alternative format (e.g., "02:30 PM")
        try {
          return DateFormat('hh:mm a').parse(timeStr);
        } catch (e) {
          // Try 24-hour format (e.g., "14:30")
          try {
            return DateFormat('HH:mm').parse(timeStr);
          } catch (e) {
            print('❌ Unable to parse time string: $timeStr');
            return null;
          }
        }
      }
    } catch (e) {
      print('❌ Error parsing time string "$timeStr": $e');
      return null;
    }
  }

  /// Cancel all AlarmManager triggers (native implementation)
  Future<void> _cancelAllEffectTriggers() async {
    try {
      await platform.invokeMethod('cancelAllEffectTriggers');
      print("🧹 All native AlarmManager triggers cancelled");
    } catch (e) {
      print('❌ Error cancelling native effect triggers: $e');
    }
  }

  /// Stop all active effects and clear alarms
  static Future<void> stopAllActiveEffects() async {
    try {
      // Cancel all active timers
      for (var timer in _activeTimers.values) {
        timer.cancel();
      }
      _activeTimers.clear();
      
      // Clear active alarms set
      _activeAlarms.clear();
      
      print("🛑 All active effects stopped");
    } catch (e) {
      print('❌ Error stopping active effects: $e');
    }
  }

  /// Clean up snoozed alarm data for a specific medicine
  Future<void> _cleanupSnoozeData(String medicineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => 
        key.startsWith('snoozed_alarm_$medicineId'));
      
      for (var key in keys) {
        await prefs.remove(key);
        print('Removed snoozed alarm data: $key');
      }
    } catch (e) {
      print('Error cleaning up snooze data: $e');
    }
  }

  /// Handle action callbacks
  static Future<void> _handleTakeMedicine(Map<String, dynamic> data) async {
    try {
      final alarmId = data['alarmId'] ?? data['id'] ?? 0;
      print("✅ Medicine taken for alarm: $alarmId");
      
      // CRITICAL: Ensure snoozed alarms are never marked as taken
      if (data['isSnooze'] == true) {
        print('⚠️ NotificationService: Attempted to mark snoozed alarm as taken, skipping');
        return;
      }
      
      // Remove from active alarms but don't clear the entire set
      _activeAlarms.remove(alarmId);
      _activeTimers[alarmId]?.cancel();
      _activeTimers.remove(alarmId);
      
      final prefs = await SharedPreferences.getInstance();
      final takenKey = 'medicine_taken_${alarmId}_${DateTime.now().toString().substring(0, 10)}';
      await prefs.setBool(takenKey, true);
      
      // Clean up any snoozed alarms for this medicine
      await _instance._cleanupSnoozeData(data['id']?.toString() ?? alarmId.toString());
      
      // Send event to stream for UI updates
      _streamController.add({
        'type': 'medicine_taken',
        'message': '✅ Medicine taken successfully',
        'data': data
      });
      
    } catch (e) {
      print('❌ Error handling take medicine: $e');
    }
  }

  /// Get the currently configured snooze duration in minutes
  Future<int> getSnoozeMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to 5 minutes if not set
      return prefs.getInt(snoozeDurationKey) ?? 5;
    } catch (e) {
      print('❌ Error getting snooze duration: $e');
      return 5; // Default fallback
    }
  }

  /// Get snoozed alarms from native side
  Future<List<Map<String, dynamic>>> getSnoozedAlarms() async {
    try {
      final result = await platform.invokeMethod<List<dynamic>>('getSnoozedAlarms');
      
      if (result == null) {
        print('ℹ️ No snoozed alarms returned from native side');
        return [];
      }
      
      final List<Map<String, dynamic>> alarms = [];
      
      for (var item in result) {
        if (item is Map) {
          final key = item['key'] as String?;
          final value = item['value'] as String?;
          
          if (key != null && value != null && key.startsWith('snoozed_alarm_')) {
            try {
              // Parse the JSON value
              final Map<String, dynamic> alarmData = json.decode(value);
              alarms.add({
                'key': key,
                'data': alarmData
              });
            } catch (e) {
              print('❌ Error parsing snoozed alarm data: $e');
            }
          }
        }
      }
      
      print('✅ Retrieved ${alarms.length} snoozed alarms from native side');
      return alarms;
      
    } catch (e) {
      print('❌ Error getting snoozed alarms: $e');
      return [];
    }
  }

  /// Handle snooze action
  static Future<void> _handleSnooze(Map<String, dynamic> data) async {
    try {
      final alarmId = data['alarmId'] ?? data['id'] ?? 0;
      print("⏰ Snooze activated for alarm: $alarmId");
      
      // Remove from active alarms but don't clear the entire set
      _activeAlarms.remove(alarmId);
      _activeTimers[alarmId]?.cancel();
      _activeTimers.remove(alarmId);
      
      // Get custom snooze duration
      final snoozeDuration = await _instance.getSnoozeMinutes();
      
      // Calculate snooze time using the custom duration
      final snoozeTime = DateTime.now().add(Duration(minutes: snoozeDuration));
      final formattedTime = DateFormat('h:mm a').format(snoozeTime);
      
      // Track snoozed alarm with its time
      final snoozeAlarmId = alarmId + 100000; // Match the native service ID generation
      _activeAlarms.add(snoozeAlarmId);
      
      // Create enhanced data for UI updates
      final enhancedData = {
        ...data,
        'snoozeTime': snoozeTime.toIso8601String(),
        'formattedSnoozeTime': formattedTime,
        'originalAlarmId': alarmId,
        'snoozeAlarmId': snoozeAlarmId,
        'snoozeDuration': snoozeDuration,
      };
      
      // Send enhanced data to stream for UI updates
      _streamController.add({
        'type': 'snooze',
        'message': '⏰ Reminder snoozed until $formattedTime',
        'data': enhancedData
      });
      
      // Save snooze info to SharedPreferences for persistence
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('snoozed_alarm_$snoozeAlarmId', jsonEncode(enhancedData));
        await prefs.setString('last_snoozed_time', snoozeTime.toIso8601String());
      } catch (e) {
        print('❌ Error saving snooze data: $e');
      }
      
    } catch (e) {
      print('❌ Error handling snooze: $e');
    }
  }

  // Static stream controller for UI updates
  static final StreamController<Map<String, dynamic>> _streamController = 
      StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of notification events for UI updates
  static Stream<Map<String, dynamic>> get notificationStream => _streamController.stream;

  /// Handle stop/dismiss action
  static Future<void> _handleStop(Map<String, dynamic> data) async {
    try {
      final alarmId = data['alarmId'] ?? data['id'] ?? 0;
      print("🛑 Alarm stopped: $alarmId");
      
      // Remove from active alarms but don't clear the entire set
      _activeAlarms.remove(alarmId);
      _activeTimers[alarmId]?.cancel();
      _activeTimers.remove(alarmId);
      
      // Send event to stream for UI updates
      _streamController.add({
        'type': 'alarm_stopped',
        'message': '🛑 Alarm stopped',
        'data': data
      });
      
    } catch (e) {
      print('❌ Error handling stop: $e');
    }
  }

  /// Handle skip action
  static Future<void> _handleSkip(Map<String, dynamic> data) async {
    try {
      final alarmId = data['alarmId'] ?? data['id'] ?? 0;
      print("⏭️ Reminder skipped: $alarmId");
      
      // Remove from active alarms but don't clear the entire set
      _activeAlarms.remove(alarmId);
      _activeTimers[alarmId]?.cancel();
      _activeTimers.remove(alarmId);
      
      // Send event to stream for UI updates
      _streamController.add({
        'type': 'reminder_skipped',
        'message': '⏭️ Reminder skipped',
        'data': data
      });
      
    } catch (e) {
      print('❌ Error handling skip: $e');
    }
  }

  /// Check various permissions required for the app
  Future<Map<String, bool>> checkPermissions() async {
    try {
      final notifications = await Permission.notification.isGranted;
      final exactAlarms = await Permission.scheduleExactAlarm.isGranted;
      final overlay = await isOverlayPermissionGranted();

      final allGranted = notifications && exactAlarms && overlay;

      return {
        'notifications': notifications,
        'exact_alarms': exactAlarms,
        'overlay': overlay,
        'all_granted': allGranted,
      };
    } catch (e) {
      print('❌ Error checking permissions: $e');
      return {
        'notifications': false,
        'exact_alarms': false,
        'overlay': false,
        'all_granted': false,
      };
    }
  }

  /// Get current native notification settings
  Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      final result = await platform.invokeMethod<Map<dynamic, dynamic>>('getNotificationSettings');
      
      // Get snooze duration from preferences
      final prefs = await SharedPreferences.getInstance();
      final snoozeDuration = prefs.getInt(snoozeDurationKey) ?? 5;
      
      return {
        'notifications_enabled': result?['notifications_enabled'] ?? false,
        'overlay_enabled': result?['overlay_enabled'] ?? false,
        'fullScreen': result?['fullScreen'] ?? true,
        'vibration': result?['vibration'] ?? true,
        'sound': result?['sound'] ?? true,
        'useDefaultAlarm': result?['useDefaultAlarm'] ?? true,
        'customSoundPath': result?['customSoundPath'] ?? '',
        'snoozeDuration': snoozeDuration,
      };
    } on MissingPluginException {
      print('⚠️ MissingPluginException: Fallback to default settings');
      return {
        'notifications_enabled': false,
        'overlay_enabled': false,
        'fullScreen': true,
        'vibration': true,
        'sound': true,
        'useDefaultAlarm': true,
        'customSoundPath': '',
        'snoozeDuration': 5,
      };
    } catch (e) {
      print('❌ Error getting notification settings: $e');
      return {
        'notifications_enabled': false,
        'overlay_enabled': false,
        'fullScreen': true,
        'vibration': true,
        'sound': true,
        'useDefaultAlarm': true,
        'customSoundPath': '',
        'snoozeDuration': 5,
      };
    }
  }

  /// Update a specific notification setting
  Future<void> updateNotificationSetting(String key, dynamic value) async {
    try {
      // Special handling for snoozeDuration which is stored in SharedPreferences
      if (key == snoozeDurationKey) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(snoozeDurationKey, value);
        print("⚙️ Updated snooze duration: $value minutes");
        
        // Also update on native side
        try {
          await platform.invokeMethod('updateSettings', {key: value});
        } catch (e) {
          // It's okay if this fails, the Flutter side is the source of truth for this setting
          print("⚠️ Native side may not support snooze duration setting: $e");
        }
      } else {
        await platform.invokeMethod('updateSettings', {key: value});
        print("⚙️ Updated native setting $key = $value");
      }
    } catch (e) {
      print('❌ Error updating notification setting: $e');
    }
  }

  /// Pick custom sound file
  Future<bool> pickCustomSound() async {
    try {
      // We need to register the method handler only once
      if (!_methodHandlerRegistered) {
        platform.setMethodCallHandler(_handleMethodCall);
        _methodHandlerRegistered = true;
        print("📱 Method channel handler registered for custom sound updates");
      }
      
      // Check for storage permission first
      PermissionStatus status;
      
      // Use appropriate permission based on Android version
      if (await _isAndroid13OrHigher()) {
        status = await Permission.audio.status;
        if (status.isDenied) {
          print("🔐 Requesting READ_MEDIA_AUDIO permission for Android 13+");
          status = await Permission.audio.request();
        }
      } else {
        status = await Permission.storage.status;
        if (status.isDenied) {
          print("🔐 Requesting READ_EXTERNAL_STORAGE permission");
          status = await Permission.storage.request();
        }
      }
      
      if (!status.isGranted) {
        print("❌ Storage permission denied");
        return false;
      }
      
      // Use FilePicker to select audio file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowCompression: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        final String? filePath = result.files.first.path;
        if (filePath != null && filePath.isNotEmpty) {
          print("🎵 Custom sound selected: $filePath");
          
          // Update the setting in native code
          await platform.invokeMethod('updateSettings', {
            customSoundPathKey: filePath
          });
          
          // Notify listeners about the new sound
          _settingsStreamController.add({
            'customSoundPath': filePath,
            'event': 'customSoundUpdated',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          });
          
          return true;
        }
      } else {
        print("⚠️ No sound file selected");
      }
      
      return false;
    } catch (e) {
      print('❌ Error picking custom sound: $e');
      return false;
    }
  }
  
  /// Helper method to check if device is running Android 13 (API 33) or higher
  Future<bool> _isAndroid13OrHigher() async {
    try {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final androidInfo = await deviceInfoPlugin.androidInfo;
      return androidInfo.version.sdkInt >= 33; // Android 13 is API 33
    } catch (e) {
      print('Error checking Android version: $e');
      return false;
    }
  }
  

  
  // Flag to ensure we only register the method handler once
  bool _methodHandlerRegistered = false;
  
  // Handle method calls from native code
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print("📱 Received method call: ${call.method}");
    
    switch (call.method) {
      case 'customSoundUpdated':
        final Map<dynamic, dynamic> args = call.arguments ?? {};
        final String customSoundPath = args['customSoundPath'] ?? '';
        print("🎵 Custom sound path updated: $customSoundPath");
        
        // Notify any UI that's listening for settings changes
        _settingsStreamController.add({
          'customSoundPath': customSoundPath,
          'event': 'customSoundUpdated',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        break;
        
      case 'notificationAction':
        final Map<dynamic, dynamic> args = call.arguments ?? {};
        final String action = args['action'] ?? '';
        final Map<String, dynamic> payload = Map<String, dynamic>.from(args['payload'] ?? {});
        print("📱 Notification action received: $action");
        
        // Handle notification action
        await handleNotificationAction(action, payload);
        break;
        
      case 'notificationDismissed':
        final Map<dynamic, dynamic> args = call.arguments ?? {};
        final int notificationId = args['notificationId'] ?? -1;
        print("📱 Notification dismissed: $notificationId");
        
        // Remove from queue if it was the current notification
        if (notificationId == _currentNotificationId) {
          _isNotificationActive = false;
          _currentNotificationId = -1;
          // Process next notification
          Timer(_queueProcessingDelay, () {
            _processNextNotification();
          });
        }
        break;
    }
    
    return null;
  }

  /// NEW: Handle notification actions
  Future<void> handleNotificationAction(String action, Map<String, dynamic> payload) async {
    try {
      switch (action.toLowerCase()) {
        case 'take':
        case 'take_medicine':
          await _handleTakeMedicine(payload);
          break;
        case 'snooze':
          await _handleSnooze(payload);
          break;
        case 'stop':
        case 'dismiss':
          await _handleStop(payload);
          break;
        case 'skip':
          await _handleSkip(payload);
          break;
        default:
          print("⚠️ Unknown notification action: $action");
      }
    } catch (e) {
      print('❌ Error handling notification action: $e');
    }
  }

  /// NEW: Get combined queue status (both alarm and notification queues)
  Future<Map<String, dynamic>> getCombinedQueueStatus() async {
    try {
      final alarmStatus = await getQueueStatus();
      final notificationStatus = getNotificationQueueStatus();
      
      return {
        'alarmQueue': alarmStatus,
        'notificationQueue': notificationStatus,
        'totalActiveItems': (alarmStatus['pendingAlarmsCount'] ?? 0) + (notificationStatus['queueSize'] ?? 0),
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting combined queue status: $e');
      return {
        'alarmQueue': {},
        'notificationQueue': {},
        'totalActiveItems': 0,
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  /// NEW: Pause notification queue processing
  Future<void> pauseNotificationQueue() async {
    try {
      if (_queueProcessorTimer != null) {
        _queueProcessorTimer!.cancel();
        _queueProcessorTimer = null;
      }
      print('⏸️ Notification queue processing paused');
    } catch (e) {
      print('❌ Error pausing notification queue: $e');
    }
  }

  /// NEW: Resume notification queue processing
  Future<void> resumeNotificationQueue() async {
    try {
      if (!_isNotificationActive && _notificationQueue.isNotEmpty) {
        _startQueueProcessing();
        print('▶️ Notification queue processing resumed');
      }
    } catch (e) {
      print('❌ Error resuming notification queue: $e');
    }
  }

  /// NEW: Get notification queue statistics
  Map<String, dynamic> getNotificationQueueStats() {
    final highPriority = _notificationQueue.where((item) => item.priority == 1).length;
    final mediumPriority = _notificationQueue.where((item) => item.priority == 2).length;
    final lowPriority = _notificationQueue.where((item) => item.priority == 3).length;
    
    final medicineNotifications = _notificationQueue.where((item) => item.type == 'medicine').length;
    final generalNotifications = _notificationQueue.where((item) => item.type == 'general').length;
    
    return {
      'totalItems': _notificationQueue.length,
      'isActive': _isNotificationActive,
      'currentId': _currentNotificationId,
      'priorityBreakdown': {
        'high': highPriority,
        'medium': mediumPriority,
        'low': lowPriority,
      },
      'typeBreakdown': {
        'medicine': medicineNotifications,
        'general': generalNotifications,
      },
      'oldestItem': _notificationQueue.isNotEmpty 
        ? _notificationQueue.first.scheduledTime.toIso8601String() 
        : null,
      'newestItem': _notificationQueue.isNotEmpty 
        ? _notificationQueue.last.scheduledTime.toIso8601String() 
        : null,
    };
  }

  /// NEW: Bulk add notifications to queue
  Future<void> bulkAddToNotificationQueue(List<NotificationData> notifications) async {
    try {
      for (final notification in notifications) {
        await addToNotificationQueue(notification);
      }
      print('📦 Bulk added ${notifications.length} notifications to queue');
    } catch (e) {
      print('❌ Error bulk adding notifications: $e');
    }
  }

  /// NEW: Clear expired notifications from queue
  Future<void> clearExpiredNotifications() async {
    try {
      final now = DateTime.now();
      final expiredCount = _notificationQueue.where((item) => 
        now.difference(item.scheduledTime).inHours >= 1
      ).length;
      
      _notificationQueue.removeWhere((item) => 
        now.difference(item.scheduledTime).inHours >= 1
      );
      
      if (expiredCount > 0) {
        await _saveNotificationQueue();
        print('🧹 Cleared $expiredCount expired notifications from queue');
      }
    } catch (e) {
      print('❌ Error clearing expired notifications: $e');
    }
  }

  /// NEW: Update notification priority in queue
  Future<void> updateNotificationPriority(int notificationId, int newPriority) async {
    try {
      final index = _notificationQueue.indexWhere((item) => item.notificationId == notificationId);
      if (index != -1) {
        final notification = _notificationQueue[index];
        final updatedNotification = NotificationData(
          notificationId: notification.notificationId,
          title: notification.title,
          body: notification.body,
          payload: notification.payload,
          scheduledTime: notification.scheduledTime,
          type: notification.type,
          priority: newPriority,
        );
        
        _notificationQueue[index] = updatedNotification;
        
        // Re-sort queue by priority and time
        _notificationQueue.sort((a, b) {
          if (a.priority != b.priority) {
            return a.priority.compareTo(b.priority);
          }
          return a.scheduledTime.compareTo(b.scheduledTime);
        });
        
        await _saveNotificationQueue();
        print('🔄 Updated notification $notificationId priority to $newPriority');
      }
    } catch (e) {
      print('❌ Error updating notification priority: $e');
    }
  }

  /// Handle various actions from notifications
  Future<void> handleAction(String action, Map<String, dynamic> data) async {
    try {
      final normalizedAction = action.toLowerCase().replaceAll(' ', '_');
      
      await platform.invokeMethod('handleAction', {
        'action': normalizedAction,
        'payload': json.encode(data),
      });
      
      switch (normalizedAction) {
        case 'take':
        case 'take_medicine':
          await _handleTakeMedicine(data);
          break;
        case 'snooze':
          await _handleSnooze(data);
          break;
        case 'stop':
        case 'dismiss':
          await _handleStop(data);
          break;
        default:
          print("⚠️ Unknown action: $normalizedAction");
      }
    } catch (e) {
      print('❌ Error handling action: $e');
    }
  }

  /// Get count of active alarms
  int get activeAlarmsCount => _activeAlarms.length;

  /// Get list of active alarm IDs
  List<int> get activeAlarmIds => _activeAlarms.toList();

  /// Get queue status from native service
  Future<Map<String, dynamic>> getQueueStatus() async {
    try {
      final result = await platform.invokeMethod<Map<dynamic, dynamic>>('getQueueStatus');
      return {
        'currentAlarmId': result?['currentAlarmId'] ?? -1,
        'isAlarmActive': result?['isAlarmActive'] ?? false,
        'pendingAlarmsCount': result?['pendingAlarmsCount'] ?? 0,
        'scheduledAlarmsCount': result?['scheduledAlarmsCount'] ?? 0,
        'pendingAlarms': (result?['pendingAlarms'] as List<dynamic>?)?.cast<int>() ?? [],
      };
    } catch (e) {
      print('❌ Error getting queue status: $e');
      return {
        'currentAlarmId': -1,
        'isAlarmActive': false,
        'pendingAlarmsCount': 0,
        'scheduledAlarmsCount': 0,
        'pendingAlarms': [],
      };
    }
  }

  /// Cancel a specific alarm by ID
  Future<void> cancelAlarm(int alarmId) async {
    try {
      if (_activeAlarms.contains(alarmId)) {
        await NotificationService.platform.invokeMethod('cancelAlarm', {'alarmId': alarmId});
        
        _activeTimers[alarmId]?.cancel();
        _activeTimers.remove(alarmId);
        _activeAlarms.remove(alarmId);
        
        print("❌ Cancelled native alarm: $alarmId");
      }
    } catch (e) {
      print('❌ Error cancelling alarm $alarmId: $e');
    }
  }

  /// Request notification permission
  Future<bool> requestNotificationPermission() async {
    try {
      final result = await platform.invokeMethod<bool>('requestNotificationPermission');
      return result ?? false;
    } catch (e) {
      print('❌ Error requesting notification permission: $e');
      return false;
    }
  }

  /// Open native app notification settings
  Future<void> openAppSettings() async {
    try {
      await platform.invokeMethod('openAppSettings');
    } catch (e) {
      print('❌ Error opening app settings: $e');
    }
  }

  /// Single reliable permission request method
  Future<bool> requestDisplayOverOtherAppsPermission() async {
    try {
      print("🔐 Starting overlay permission request...");
      
      // Check current status first
      bool isGranted = await isOverlayPermissionGranted();
      if (isGranted) {
        print("✅ Permission already granted");
        return true;
      }
      
      // Request permission via native method
      await platform.invokeMethod('requestOverlayPermission');
      
      // Wait for user action
      await Future.delayed(Duration(milliseconds: 2000));
      
      // Check final status
      bool finalStatus = await isOverlayPermissionGranted();
      print("🔐 Final permission status: $finalStatus");
      
      return finalStatus;
      
    } catch (e) {
      print('❌ Error requesting overlay permission: $e');
      return false;
    }
  }

  /// Opens the system settings page for "Display over other apps" permission.
  Future<void> openDisplayOverOtherAppsSettings() async {
    try {
      await SystemAlertWindow.requestPermissions();
    } catch (e) {
      print('Error opening overlay settings: $e');
    }
  }

  /// Dispose method to clean up resources
  Future<void> dispose() async {
    final activeAlarmsToCancel = List<int>.from(_activeAlarms);
    final timersToCancel = Map<int, Timer>.from(_activeTimers);
    
    try {
      // Cancel all timers
      for (var timer in timersToCancel.values) {
        timer.cancel();
      }
      _activeTimers.clear();
      
      // Cancel all alarms
      for (var alarmId in activeAlarmsToCancel) {
        await cancelAlarm(alarmId);
      }
      _activeAlarms.clear();
      
      // NEW: Clean up notification queue
      if (_queueProcessorTimer != null) {
        _queueProcessorTimer!.cancel();
        _queueProcessorTimer = null;
      }
      
      // Save current queue state before clearing
      await _saveNotificationQueue();
      
      await _cancelAllEffectTriggers();
      
      _isInitialized = false;
      print("🧹 Native NotificationService disposed successfully");
    } catch (e) {
      print('❌ Error disposing NotificationService: $e');
    }
  }

  // Add stream controller for settings updates
  final StreamController<Map<String, dynamic>> _settingsStreamController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  /// Stream of settings updates
  Stream<Map<String, dynamic>> get onSettingsChanged => _settingsStreamController.stream;
}

/*
📋 NOTIFICATION QUEUE SYSTEM USAGE EXAMPLES

The notification queue system works similarly to the alarm queue system, providing
sequential processing of notifications to prevent overwhelming the user.

🔧 ADVANCED USAGE:

// Bulk add notifications
final notifications = [
  NotificationData(
    notificationId: 1,
    title: 'Medicine 1',
    body: 'Take Medicine 1',
    payload: {'medicineId': 'med_1'},
    scheduledTime: DateTime.now().add(Duration(minutes: 1)),
    type: 'medicine',
    priority: 1,
  ),
  NotificationData(
    notificationId: 2,
    title: 'Medicine 2',
    body: 'Take Medicine 2',
    payload: {'medicineId': 'med_2'},
    scheduledTime: DateTime.now().add(Duration(minutes: 2)),
    type: 'medicine',
    priority: 1,
  ),
];

await NotificationService().bulkAddToNotificationQueue(notifications);

// Pause/Resume queue processing
await NotificationService().pauseNotificationQueue();
await NotificationService().resumeNotificationQueue();

// Update notification priority
await NotificationService().updateNotificationPriority(12345, 1);

// Clear expired notifications
await NotificationService().clearExpiredNotifications();

// Remove specific notification
await NotificationService().removeFromNotificationQueue(12345);

// Clear entire queue
await NotificationService().clearNotificationQueue();

🎯 QUEUE SYSTEM FEATURES:

✅ Sequential Processing: Only one notification active at a time
✅ Priority-based Sorting: High priority notifications first
✅ Persistent Storage: Queue survives app restarts
✅ Automatic Cleanup: Expired notifications removed
✅ Bulk Operations: Add multiple notifications efficiently
✅ Statistics & Monitoring: Detailed queue analytics
✅ Pause/Resume: Control queue processing
✅ Error Handling: Graceful failure recovery

🔄 QUEUE PROCESSING FLOW:

1. Notification added to queue → Sorted by priority & time
2. If no notification active → Process immediately
3. If notification active → Wait in queue
4. Current notification dismissed → Process next in queue
5. 2-second delay between notifications
6. Automatic cleanup of expired items

📊 PRIORITY LEVELS:
- 1 = High Priority (Medicine reminders, urgent alerts)
- 2 = Medium Priority (General reminders, appointments)
- 3 = Low Priority (Informational notifications)

📱 NOTIFICATION TYPES:
- 'medicine' = Medicine-related notifications
- 'general' = General app notifications
- 'reminder' = Reminder notifications
- 'alert' = Alert notifications
*/
