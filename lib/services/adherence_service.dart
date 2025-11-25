import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import './medicine_service.dart'; // Added import for MedicineService
import './medicine_action_service.dart'; // Added import for MedicineActionService

class AdherenceService {
  static final AdherenceService _instance = AdherenceService._internal();
  factory AdherenceService() => _instance;
  AdherenceService._internal();

  // Cache for local data
  final Map<String, dynamic> _localCache = {};
  bool _isInitialized = false;
  DateTime? _lastSyncTime;

  // Initialize local cache
  Future<void> _initializeCache() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheData = prefs.getString('adherence_local_cache');
      if (cacheData != null) {
        _localCache.addAll(jsonDecode(cacheData));
      }
      
      final lastSyncStr = prefs.getString('adherence_last_sync');
      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.parse(lastSyncStr);
      }
      
      _isInitialized = true;
      print('✅ AdherenceService: Local cache initialized');
    } catch (e) {
      print('❌ AdherenceService: Error initializing cache: $e');
    }
  }

  // Save medicine action locally and queue for database sync
  Future<void> saveMedicineAction({
    required String userId,
    required String medicineId,
    required String medicineName,
    required String action, // 'taken', 'missed', 'skipped'
    required String date,
    String? time,
    String? notes,
    Map<String, dynamic>? medicineData,
  }) async {
    // CRITICAL: Ensure snooze actions are never processed as adherence actions
    if (action.toLowerCase() == 'snooze') {
      print('⚠️ AdherenceService: Snooze action detected, skipping adherence tracking');
      return;
    }
    try {
      await _initializeCache();
      
      print('💾 AdherenceService: Saving medicine action locally');
      
      final actionData = {
        'userId': userId,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'action': action,
        'date': date,
        'time': time ?? DateFormat('HH:mm').format(DateTime.now()),
        'notes': notes,
        'medicineData': medicineData,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': false, // Mark as not synced to database
      };

      // Store locally
      await _saveActionLocally(actionData);
      
      // Queue for database sync
      await _queueForSync(actionData);
      
      print('✅ AdherenceService: Medicine action saved locally');
    } catch (e) {
      print('❌ AdherenceService: Error saving medicine action: $e');
      throw Exception('Failed to save medicine action: $e');
    }
  }

  // Save medicine action using document-based approach (optimized for Firebase usage)
  Future<void> saveMedicineActionDocumentBased({
    required String userId,
    required String medicineId,
    required String medicineName,
    required String action, // 'taken', 'missed', 'skipped'
    required String date,
    String? time,
    String? notes,
    Map<String, dynamic>? medicineData,
  }) async {
    // CRITICAL: Ensure snooze actions are never processed as adherence actions
    if (action.toLowerCase() == 'snooze') {
      print('⚠️ AdherenceService: Snooze action detected, skipping adherence tracking');
      return;
    }
    try {
      print('💾 AdherenceService: Saving medicine action (local-first approach)');
      
      // Extract the original medicine ID from composite ID if needed
      String originalMedicineId = medicineId;
      if (medicineId.contains('_') && medicineId.contains(date)) {
        // This is a composite ID like "originalId_selectedDate"
        originalMedicineId = medicineId.substring(0, medicineId.lastIndexOf('_'));
        print('🔧 AdherenceService: Extracted original medicine ID: $originalMedicineId from composite: $medicineId');
      }
      
      // Update medicine completion status in document-based storage (this is critical for UI)
      final medicineService = MedicineService();
      final isCompleted = action == 'taken';
      
      await medicineService.updateMedicineCompletionDocumentBased(
        userId,
        originalMedicineId, // Use the original medicine ID
        date,
        isCompleted,
        completedAt: isCompleted ? DateTime.now() : null,
      );
      
      // Prepare adherence data for local storage
      final actionData = {
        'userId': userId,
        'medicineId': originalMedicineId, // Store the original medicine ID
        'medicineName': medicineName,
        'action': action,
        'date': date,
        'time': time ?? DateFormat('HH:mm').format(DateTime.now()),
        'notes': notes,
        'medicineData': medicineData,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'synced': false, // Mark as not synced to Firebase yet
        'originalCompositeId': medicineId, // Store the original composite ID for reference
        'uniqueId': '${originalMedicineId}_${date}_${time?.replaceAll(':', '_') ?? DateTime.now().millisecondsSinceEpoch}',
      };

      // Store locally first (immediate)
      await _saveActionLocally(actionData);
      
      // Queue for Firebase sync (deferred)
      await _queueForSync(actionData);
      
      print('✅ AdherenceService: Medicine action saved locally, queued for Firebase sync');
    } catch (e) {
      print('❌ AdherenceService: Error saving medicine action: $e');
      throw Exception('Failed to save medicine action: $e');
    }
  }

  // Save action to local storage
  Future<void> _saveActionLocally(Map<String, dynamic> actionData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing local actions
      final localActionsJson = prefs.getString('adherence_local_actions') ?? '[]';
      List<dynamic> localActions = [];
      
      try {
        localActions = jsonDecode(localActionsJson);
        if (localActions is! List) localActions = [];
      } catch (e) {
        print('⚠️ AdherenceService: Error parsing local actions, resetting');
        localActions = [];
      }
      
      // Check for duplicate action to prevent double counting
      final medicineId = actionData['medicineId'] as String? ?? '';
      final date = actionData['date'] as String? ?? '';
      final time = actionData['time'] as String? ?? '';
      final action = actionData['action'] as String? ?? '';
      
      // Create a unique key for this action
      final uniqueKey = '${medicineId}_${date}_${time.replaceAll(':', '_')}';
      
      // Check if this exact action already exists
      final existingIndex = localActions.indexWhere((existingAction) => 
        existingAction is Map &&
        existingAction['medicineId'] == medicineId &&
        existingAction['date'] == date &&
        existingAction['time'] == time &&
        existingAction['action'] == action);
      
      if (existingIndex >= 0) {
        print('ℹ️ AdherenceService: Action already exists in local storage, skipping duplicate: $uniqueKey');
        return;
      }
      
      // Also check for any action with the same unique key (medicine, date, time) but different action
      final duplicateKeyIndex = localActions.indexWhere((existingAction) => 
        existingAction is Map &&
        existingAction['medicineId'] == medicineId &&
        existingAction['date'] == date &&
        existingAction['time'] == time);
      
      if (duplicateKeyIndex >= 0) {
        // Update the existing action with the new action type
        localActions[duplicateKeyIndex] = actionData;
        print('🔄 AdherenceService: Updated existing action with new status: $uniqueKey (${localActions[duplicateKeyIndex]['action']} -> $action)');
      } else {
        // Add new action
        localActions.add(actionData);
        print('➕ AdherenceService: Added new action: $uniqueKey');
      }
      
      // Limit to 1000 actions to prevent memory issues
      if (localActions.length > 1000) {
        localActions.removeRange(0, localActions.length - 1000);
      }
      
      // Save back to SharedPreferences
      await prefs.setString('adherence_local_actions', jsonEncode(localActions));
      
      // Update cache
      _localCache['local_actions'] = localActions;
      
      print('✅ AdherenceService: Action saved to local storage');
      
    } catch (e) {
      print('❌ AdherenceService: Error saving action locally: $e');
    }
  }

  // Queue action for database sync
  Future<void> _queueForSync(Map<String, dynamic> actionData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Get existing sync queue
      final syncQueueJson = prefs.getString('adherence_sync_queue') ?? '[]';
      List<dynamic> syncQueue = [];
      
      try {
        syncQueue = jsonDecode(syncQueueJson);
        if (syncQueue is! List) syncQueue = [];
      } catch (e) {
        print('⚠️ AdherenceService: Error parsing sync queue, resetting');
        syncQueue = [];
      }
      
      // Add to sync queue
      syncQueue.add(actionData);
      
      // Save sync queue
      await prefs.setString('adherence_sync_queue', jsonEncode(syncQueue));
      
    } catch (e) {
      print('❌ AdherenceService: Error queuing for sync: $e');
    }
  }

  // Sync local data to database (optimized for Firebase usage)
  Future<void> syncToDatabase({String? userId, bool forceSync = false}) async {
    try {
      await _initializeCache();
      
      // Check if we should sync
      if (!forceSync && !_shouldSync()) {
        print('ℹ️ AdherenceService: Not time to sync yet (last sync: $_lastSyncTime)');
        return;
      }
      
      print('🔄 AdherenceService: Starting database sync (${forceSync ? 'forced' : 'scheduled'})');
      
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = userId ?? prefs.getString('user_id');
      if (currentUserId == null || currentUserId.isEmpty) {
        throw Exception('User ID not found. Please restart the app or re-enter your name.');
      }
      
      // Get sync queue
      final syncQueueJson = prefs.getString('adherence_sync_queue') ?? '[]';
      List<dynamic> syncQueue = [];
      
      try {
        syncQueue = jsonDecode(syncQueueJson);
        if (syncQueue is! List) syncQueue = [];
      } catch (e) {
        print('⚠️ AdherenceService: Error parsing sync queue');
        return;
      }
      
      if (syncQueue.isEmpty) {
        print('ℹ️ AdherenceService: No actions to sync');
        return;
      }
      
      print('📊 AdherenceService: Syncing ${syncQueue.length} actions to Firebase');
      
      // Process in batches to avoid Firebase limits (500 operations per batch)
      const int batchSize = 400; // Conservative limit
      int totalSynced = 0;
      
      for (int i = 0; i < syncQueue.length; i += batchSize) {
        final batchEnd = (i + batchSize < syncQueue.length) ? i + batchSize : syncQueue.length;
        final batch = syncQueue.sublist(i, batchEnd);
        
        print('📦 AdherenceService: Processing batch ${(i ~/ batchSize) + 1} (${batch.length} actions)');
        
        // Create batch write
        final firestoreBatch = FirebaseFirestore.instance.batch();
        int batchSynced = 0;
        
        for (final actionData in batch) {
          try {
            // Use uniqueId if available, otherwise generate one
            final uniqueId = actionData['uniqueId'] ?? 
                '${actionData['medicineId']}_${actionData['date']}_${(actionData['time'] as String).replaceAll(':', '_')}';
            
            // Create document reference with unique ID
            final docRef = FirebaseFirestore.instance
                .collection('users')
                .doc(currentUserId)
                .collection('adherence')
                .doc(uniqueId);
            
            // Prepare data for Firebase (remove local-only fields)
            final firebaseData = Map<String, dynamic>.from(actionData);
            firebaseData.remove('synced'); // Remove local sync flag
            firebaseData['syncedAt'] = DateTime.now().toIso8601String();
            firebaseData['firebaseId'] = uniqueId;
            
            // Add to batch
            firestoreBatch.set(docRef, firebaseData, SetOptions(merge: true));
            batchSynced++;
            
          } catch (e) {
            print('❌ AdherenceService: Error preparing action for sync: $e');
          }
        }
        
        // Commit this batch
        try {
          await firestoreBatch.commit();
          totalSynced += batchSynced;
          print('✅ AdherenceService: Batch ${(i ~/ batchSize) + 1} synced successfully ($batchSynced actions)');
        } catch (e) {
          print('❌ AdherenceService: Error committing batch ${(i ~/ batchSize) + 1}: $e');
          // Continue with next batch instead of failing completely
        }
        
        // Small delay between batches to avoid overwhelming Firebase
        if (batchEnd < syncQueue.length) {
          await Future.delayed(Duration(milliseconds: 100));
        }
      }
      
      // Clear sync queue only if all actions were synced
      if (totalSynced == syncQueue.length) {
        await prefs.remove('adherence_sync_queue');
        print('🧹 AdherenceService: Sync queue cleared');
      } else {
        // Remove only the synced actions from queue
        final remainingActions = syncQueue.sublist(totalSynced);
        await prefs.setString('adherence_sync_queue', jsonEncode(remainingActions));
        print('⚠️ AdherenceService: ${remainingActions.length} actions remaining in sync queue');
      }
      
      // Update last sync time
      _lastSyncTime = DateTime.now();
      await prefs.setString('adherence_last_sync', _lastSyncTime!.toIso8601String());
      
      print('✅ AdherenceService: Successfully synced $totalSynced/$syncQueue.length actions to Firebase');
      
    } catch (e) {
      print('❌ AdherenceService: Error syncing to database: $e');
    }
  }

  // Get adherence data (local-first approach to reduce Firebase reads)
  Future<List<Map<String, dynamic>>> getAdherenceData({
    required String userId,
    String? startDate,
    String? endDate,
    String? medicineId,
    bool forceSync = false,
    bool includeFirebase = false, // New parameter to control Firebase reads
  }) async {
    try {
      await _initializeCache();
      
      // Get local data first (always available)
      final localData = await _getLocalAdherenceData(userId: userId);
      
      List<Map<String, dynamic>> databaseData = [];
      
      // Only fetch from Firebase if explicitly requested or if local data is insufficient
      if (includeFirebase || forceSync || _shouldSync()) {
        // Sync local data to Firebase first
        if (forceSync || _shouldSync()) {
          await syncToDatabase(userId: userId, forceSync: forceSync);
        }
        
        // Then fetch from Firebase if requested
        if (includeFirebase) {
          databaseData = await _getDatabaseAdherenceData(
            userId: userId,
            startDate: startDate,
            endDate: endDate,
            medicineId: medicineId,
          );
        }
      }
      
      // Combine data (local data takes precedence for recent actions)
      final combinedData = [...localData, ...databaseData];
      
      // Apply filters
      final filteredData = combinedData.where((action) {
        if (startDate != null && action['date'] < startDate) return false;
        if (endDate != null && action['date'] > endDate) return false;
        if (medicineId != null) {
          // Handle composite ID matching
          final actionMedicineId = action['medicineId'] as String?;
          final actionCompositeId = action['originalCompositeId'] as String?;
          
          if (actionMedicineId == medicineId || actionCompositeId == medicineId) {
            return true;
          }
          
          // Check if medicineId is a composite ID and match against original
          if (medicineId.contains('_') && actionMedicineId != null) {
            final extractedId = medicineId.substring(0, medicineId.lastIndexOf('_'));
            if (actionMedicineId == extractedId) {
              return true;
            }
          }
          
          return false;
        }
        return true;
      }).toList();
      
      // Sort by date descending
      filteredData.sort((a, b) => b['date'].compareTo(a['date']));
      
      print('✅ AdherenceService: Retrieved ${filteredData.length} adherence records (${localData.length} local, ${databaseData.length} database)');
      return filteredData;
      
    } catch (e) {
      print('❌ AdherenceService: Error getting adherence data: $e');
      return [];
    }
  }

  // Get local adherence data
  Future<List<Map<String, dynamic>>> _getLocalAdherenceData({required String userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localActionsJson = prefs.getString('adherence_local_actions') ?? '[]';
      
      List<dynamic> localActions = [];
      try {
        localActions = jsonDecode(localActionsJson);
        if (localActions is! List) localActions = [];
      } catch (e) {
        return [];
      }
      
      return localActions
          .where((action) => action['userId'] == userId)
          .map((action) => Map<String, dynamic>.from(action))
          .toList();
      
    } catch (e) {
      print('❌ AdherenceService: Error getting local adherence data: $e');
      return [];
    }
  }

  // Get database adherence data
  Future<List<Map<String, dynamic>>> _getDatabaseAdherenceData({
    required String userId,
    String? startDate,
    String? endDate,
    String? medicineId,
  }) async {
    try {
      print('🔍 AdherenceService: Getting database adherence data for user: $userId');
      
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('adherence');

      // Apply filters
      if (startDate != null) {
        query = query.where('date', isGreaterThanOrEqualTo: startDate);
        print('🔍 AdherenceService: Applied startDate filter: $startDate');
      }
      if (endDate != null) {
        query = query.where('date', isLessThanOrEqualTo: endDate);
        print('🔍 AdherenceService: Applied endDate filter: $endDate');
      }
      
      // Handle medicineId filter - we'll filter in memory for composite IDs
      if (medicineId != null && !medicineId.contains('_')) {
        // For non-composite IDs, we can use the database query
        query = query.where('medicineId', isEqualTo: medicineId);
        print('🔍 AdherenceService: Applied medicineId filter: $medicineId');
      }

      final snapshot = await query.orderBy('date', descending: true).get();
      print('🔍 AdherenceService: Found ${snapshot.docs.length} documents in database');
      
      List<Map<String, dynamic>> results = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) {
          return <String, dynamic>{
            'id': doc.id,
            'error': 'Document data is null',
          };
        }
        return {
          ...data,
          'id': doc.id,
        };
      }).toList();
      
      // Apply medicineId filter in memory for composite IDs
      if (medicineId != null && medicineId.contains('_')) {
        print('🔍 AdherenceService: Applying composite ID filter in memory: $medicineId');
        results = results.where((action) {
          final actionMedicineId = action['medicineId'] as String?;
          final actionCompositeId = action['originalCompositeId'] as String?;
          
          if (actionMedicineId == medicineId || actionCompositeId == medicineId) {
            return true;
          }
          
          // Check if medicineId is a composite ID and match against original
          if (actionMedicineId != null) {
            final extractedId = medicineId.substring(0, medicineId.lastIndexOf('_'));
            if (actionMedicineId == extractedId) {
              return true;
            }
          }
          
          return false;
        }).toList();
        print('🔍 AdherenceService: After composite ID filter: ${results.length} results');
      }
      
      print('✅ AdherenceService: Retrieved ${results.length} records from database');
      return results;
      
    } catch (e) {
      print('❌ AdherenceService: Error getting database adherence data: $e');
      return [];
    }
  }

  // Check if we should sync to database
  bool _shouldSync() {
    if (_lastSyncTime == null) return true;
    
    // Sync if it's been more than 2 hours (more frequent for better data consistency)
    final hoursSinceLastSync = DateTime.now().difference(_lastSyncTime!).inHours;
    return hoursSinceLastSync >= 2;
  }
  
  // Check if we should force sync (e.g., when app is closing)
  bool _shouldForceSync() {
    if (_lastSyncTime == null) return true;
    
    // Force sync if it's been more than 6 hours
    final hoursSinceLastSync = DateTime.now().difference(_lastSyncTime!).inHours;
    return hoursSinceLastSync >= 6;
  }

  // Get daily adherence summary (local + database)
  Future<Map<String, dynamic>> getDailyAdherenceSummary({
    required String userId,
    required String date,
  }) async {
    try {
      final adherenceData = await getAdherenceData(
        userId: userId,
        startDate: date,
        endDate: date,
      );

      int taken = 0;
      int missed = 0;
      int skipped = 0;
      Map<String, dynamic> medicines = {};

      for (final action in adherenceData) {
        final actionType = action['action'] as String;
        final medicineId = action['medicineId'] as String;
        
        switch (actionType) {
          case 'taken':
            taken++;
            break;
          case 'missed':
            missed++;
            break;
          case 'skipped':
            skipped++;
            break;
        }
        
        medicines[medicineId] = actionType;
      }

      final total = taken + missed + skipped;
      final adherenceRate = total > 0 ? (taken / total) * 100 : 0.0;

      return {
        'date': date,
        'taken': taken,
        'missed': missed,
        'skipped': skipped,
        'total': total,
        'adherenceRate': adherenceRate,
        'medicines': medicines,
      };
    } catch (e) {
      print('❌ AdherenceService: Error getting daily adherence summary: $e');
      return {
        'date': date,
        'taken': 0,
        'missed': 0,
        'skipped': 0,
        'total': 0,
        'adherenceRate': 0.0,
        'medicines': {},
      };
    }
  }

  // Get adherence statistics (local + database)
  Future<Map<String, dynamic>> getAdherenceStatistics({
    required String userId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final adherenceData = await getAdherenceData(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
      );

      int totalTaken = 0;
      int totalMissed = 0;
      int totalSkipped = 0;
      Map<String, int> medicineStats = {};

      for (final action in adherenceData) {
        final actionType = action['action'] as String;
        final medicineId = action['medicineId'] as String;
        
        switch (actionType) {
          case 'taken':
            totalTaken++;
            medicineStats[medicineId] = (medicineStats[medicineId] ?? 0) + 1;
            break;
          case 'missed':
            totalMissed++;
            break;
          case 'skipped':
            totalSkipped++;
            break;
        }
      }

      final totalScheduled = totalTaken + totalMissed + totalSkipped;
      final adherenceRate = totalScheduled > 0 ? (totalTaken / totalScheduled) * 100 : 0.0;

      return {
        'totalTaken': totalTaken,
        'totalMissed': totalMissed,
        'totalSkipped': totalSkipped,
        'totalScheduled': totalScheduled,
        'adherenceRate': adherenceRate,
        'medicineStats': medicineStats,
        'period': {
          'startDate': startDate,
          'endDate': endDate,
        },
      };
    } catch (e) {
      print('❌ AdherenceService: Error getting adherence statistics: $e');
      return {
        'totalTaken': 0,
        'totalMissed': 0,
        'totalSkipped': 0,
        'totalScheduled': 0,
        'adherenceRate': 0.0,
        'medicineStats': {},
        'period': {
          'startDate': startDate,
          'endDate': endDate,
        },
      };
    }
  }

  // Get adherence streak (local + database)
  Future<int> getAdherenceStreak({
    required String userId,
    required String medicineId,
  }) async {
    try {
      final adherenceData = await getAdherenceData(
        userId: userId,
        medicineId: medicineId,
      );

      // Sort by date in descending order
      adherenceData.sort((a, b) => b['date'].compareTo(a['date']));

      int streak = 0;
      DateTime? lastDate;

      for (final action in adherenceData) {
        final actionType = action['action'] as String;
        final dateStr = action['date'] as String;
        final date = DateTime.parse(dateStr);

        if (actionType == 'taken') {
          if (lastDate == null) {
            streak = 1;
            lastDate = date;
          } else {
            final daysDifference = lastDate.difference(date).inDays;
            if (daysDifference == 1) {
              streak++;
              lastDate = date;
            } else {
              break;
            }
          }
        } else {
          break; // Streak ends if medicine was missed or skipped
        }
      }

      print('✅ AdherenceService: Adherence streak is $streak days');
      return streak;
    } catch (e) {
      print('❌ AdherenceService: Error calculating adherence streak: $e');
      return 0;
    }
  }

  // Get weekly adherence summary for charts
  Future<List<Map<String, dynamic>>> getWeeklyAdherenceSummary({
    required String userId,
    int weeks = 4,
  }) async {
    try {
      // Clear cache to ensure fresh data
      await clearLocalCache();
      
      final medicineActionService = MedicineActionService();
      final allActions = await medicineActionService.getAllMedicineActions();
      final userActions = allActions
          .where((action) {
            final actionUserId = action['userId'] as String?;
            if (actionUserId == null || actionUserId.isEmpty) {
              return true; // Backward compatibility for older records
            }
            return actionUserId == userId;
          })
          .map((action) => Map<String, dynamic>.from(action))
          .toList();
      
      print('📊 AdherenceService: Processing ${userActions.length} user actions for weekly summary');
      
      final now = DateTime.now();
      final List<Map<String, dynamic>> weeklySummaries = [];
      
      for (int i = 0; i < weeks; i++) {
        DateTime weekStart;
        DateTime weekEnd;
        
        if (i == 0) {
          final daysFromMonday = now.weekday - 1; // 0 = Monday
          weekStart = now.subtract(Duration(days: daysFromMonday));
          weekEnd = weekStart.add(const Duration(days: 6));
        } else {
          final daysFromMonday = now.weekday - 1;
          final currentWeekStart = now.subtract(Duration(days: daysFromMonday));
          weekStart = currentWeekStart.subtract(Duration(days: 7 * i));
          weekEnd = weekStart.add(const Duration(days: 6));
        }
        
        final startDate = DateFormat('yyyy-MM-dd').format(weekStart);
        final endDate = DateFormat('yyyy-MM-dd').format(weekEnd);
        
        print('📅 AdherenceService: Week ${i + 1} - $startDate to $endDate');
        
        final weekActions = userActions.where((action) {
          final actionDate = action['date'] as String? ?? '';
          return actionDate.compareTo(startDate) >= 0 && actionDate.compareTo(endDate) <= 0;
        }).toList();
        
        print('📊 AdherenceService: Found ${weekActions.length} actions for week ${i + 1}');
        
        final actionsByDay = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        for (var action in weekActions) {
          final date = action['date'] as String? ?? '';
          final actionMedicineId = action['medicineId'] ?? action['id'] ?? '';
          
          actionsByDay.putIfAbsent(date, () => {});
          actionsByDay[date]!.putIfAbsent(actionMedicineId, () => []);
          actionsByDay[date]![actionMedicineId]!.add(action);
        }
        
        int totalTaken = 0;
        int totalMissed = 0;
        int totalSkipped = 0;
        
        actionsByDay.forEach((_, medicineActions) {
          medicineActions.forEach((_, actions) {
            actions.sort((a, b) {
              final timeA = (a['time']?.toString() ?? '');
              final timeB = (b['time']?.toString() ?? '');
              return timeB.compareTo(timeA);
            });
            final latestAction = actions.first;
            
            switch (latestAction['action']) {
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
        });
        
        final totalScheduled = totalTaken + totalMissed + totalSkipped;
        final adherenceRate = totalScheduled > 0 ? (totalTaken / totalScheduled) * 100 : 0.0;
        
        weeklySummaries.add({
          'week': i + 1,
          'startDate': startDate,
          'endDate': endDate,
          'statistics': {
            'totalTaken': totalTaken,
            'totalMissed': totalMissed,
            'totalSkipped': totalSkipped,
            'totalScheduled': totalScheduled,
            'adherenceRate': adherenceRate,
          },
        });
      }
      
      return weeklySummaries;
    } catch (e, stack) {
      print('❌ AdherenceService: Error getting weekly adherence summary: $e');
      print('❌ AdherenceService: Stack trace: $stack');
      return [];
    }
  }

  // Get monthly adherence summary
  Future<List<Map<String, dynamic>>> getMonthlyAdherenceSummary({
    required String userId,
    int months = 6,
  }) async {
    try {
      // Clear cache to ensure fresh data
      await clearLocalCache();
      
      // Use MedicineActionService to get the latest actions
      final medicineActionService = MedicineActionService();
      final allActions = await medicineActionService.getAllMedicineActions();
      final userActions = allActions
          .where((action) {
            final actionUserId = action['userId'] as String?;
            if (actionUserId == null || actionUserId.isEmpty) {
              return true;
            }
            return actionUserId == userId;
          })
          .map((action) => Map<String, dynamic>.from(action))
          .toList();
      
      print('📊 AdherenceService: Processing ${userActions.length} user actions for monthly summary');
      
      final now = DateTime.now();
      final List<Map<String, dynamic>> monthlySummaries = [];
      
      for (int i = 0; i < months; i++) {
        final monthStart = DateTime(now.year, now.month - i, 1);
        final monthEnd = DateTime(now.year, now.month - i + 1, 0);
        
        final startDate = DateFormat('yyyy-MM-dd').format(monthStart);
        final endDate = DateFormat('yyyy-MM-dd').format(monthEnd);
        
        print('📅 AdherenceService: Month ${i + 1} - $startDate to $endDate');
        
        // Filter actions for this month
        final monthActions = userActions.where((action) {
          final actionDate = action['date'] as String? ?? '';
          return actionDate.compareTo(startDate) >= 0 && actionDate.compareTo(endDate) <= 0;
        }).toList();
        
        print('📊 AdherenceService: Found ${monthActions.length} actions for month ${i + 1}');
        
        // Group actions by date and medicine to avoid duplicates
        final actionsByDay = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        for (var action in monthActions) {
          final date = action['date'] as String;
          final medicineId = action['medicineId'] ?? action['id'] ?? '';
          
          if (!actionsByDay.containsKey(date)) {
            actionsByDay[date] = {};
          }
          if (!actionsByDay[date]!.containsKey(medicineId)) {
            actionsByDay[date]![medicineId] = [];
          }
          actionsByDay[date]![medicineId]!.add(action);
        }
        
        int totalTaken = 0;
        int totalMissed = 0;
        int totalSkipped = 0;
        
        // Count unique medicine actions per day (latest action wins)
        actionsByDay.forEach((date, medicineActions) {
          medicineActions.forEach((medicineId, actions) {
            // Sort actions by time to get the latest status
            actions.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
            final latestAction = actions.first;
            
            switch (latestAction['action']) {
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
        });
        
        final totalScheduled = totalTaken + totalMissed + totalSkipped;
        final adherenceRate = totalScheduled > 0 ? (totalTaken / totalScheduled) * 100 : 0.0;
        
        print('📈 AdherenceService: Month ${i + 1} - Taken: $totalTaken, Missed: $totalMissed, Skipped: $totalSkipped, Rate: ${adherenceRate.toStringAsFixed(1)}%');
        
        monthlySummaries.add({
          'month': DateFormat('MMMM yyyy').format(monthStart),
          'startDate': startDate,
          'endDate': endDate,
          'statistics': {
            'totalTaken': totalTaken,
            'totalMissed': totalMissed,
            'totalSkipped': totalSkipped,
            'totalScheduled': totalScheduled,
            'adherenceRate': adherenceRate,
          },
        });
      }
      
      return monthlySummaries;
    } catch (e) {
      print('❌ AdherenceService: Error getting monthly adherence summary: $e');
      return [];
    }
  }

  // Get most recent adherence actions for activity feeds
  Future<List<Map<String, dynamic>>> getRecentAdherenceData({
    required String userId,
    int limit = 50,
    bool includeFirebase = false,
  }) async {
    try {
      final adherenceData = await getAdherenceData(
        userId: userId,
        includeFirebase: includeFirebase,
      );
      
      DateTime parseActionDate(Map<String, dynamic> action) {
        final dateStr = action['date']?.toString();
        final timeStr = action['time']?.toString();
        
        if (dateStr == null || dateStr.isEmpty) {
          return DateTime.fromMillisecondsSinceEpoch(0);
        }
        
        try {
          if (timeStr != null && timeStr.isNotEmpty) {
            final normalizedTime = timeStr.length == 5 ? timeStr : timeStr.padLeft(5, '0');
            return DateFormat('yyyy-MM-dd HH:mm').parse('$dateStr $normalizedTime');
          }
          return DateFormat('yyyy-MM-dd').parse(dateStr);
        } catch (_) {
          return DateTime.tryParse('${dateStr}T${timeStr ?? '00:00'}') ??
              DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
      
      adherenceData.sort((a, b) => parseActionDate(b).compareTo(parseActionDate(a)));
      
      return adherenceData.take(limit).map((action) => Map<String, dynamic>.from(action)).toList();
    } catch (e, stack) {
      print('❌ AdherenceService: Error getting recent adherence data: $e');
      print('❌ AdherenceService: Stack trace: $stack');
      return [];
    }
  }

  // Force sync to database
  Future<void> forceSyncToDatabase({String? userId}) async {
    await syncToDatabase(userId: userId, forceSync: true);
  }
  
  // Sync when app is closing or user requests
  Future<void> syncOnAppClose({String? userId}) async {
    try {
      print('🔄 AdherenceService: Syncing on app close');
      
      // Check if we should force sync
      if (_shouldForceSync()) {
        await syncToDatabase(userId: userId, forceSync: true);
      } else {
        // Just do a regular sync if needed
        await syncToDatabase(userId: userId, forceSync: false);
      }
    } catch (e) {
      print('❌ AdherenceService: Error syncing on app close: $e');
    }
  }
  
  // Automatic sync trigger (called by background service)
  Future<void> autoSync({String? userId}) async {
    try {
      print('🔄 AdherenceService: Automatic sync triggered');
      await syncToDatabase(userId: userId, forceSync: false);
    } catch (e) {
      print('❌ AdherenceService: Error in automatic sync: $e');
    }
  }

  // Clear local cache to ensure fresh data
  Future<void> clearLocalCache() async {
    try {
      _localCache.clear();
      print('🧹 AdherenceService: Local cache cleared');
    } catch (e) {
      print('❌ AdherenceService: Error clearing local cache: $e');
    }
  }

  // Get sync status and pending actions
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      await _initializeCache();
      
      final prefs = await SharedPreferences.getInstance();
      final syncQueueJson = prefs.getString('adherence_sync_queue') ?? '[]';
      final localActionsJson = prefs.getString('adherence_local_actions') ?? '[]';
      
      List<dynamic> syncQueue = [];
      List<dynamic> localActions = [];
      
      try {
        syncQueue = jsonDecode(syncQueueJson);
        localActions = jsonDecode(localActionsJson);
      } catch (e) {
        // Handle parse errors
      }
      
      // Calculate unsynced actions
      final unsyncedActions = localActions.where((action) => 
        action is Map && action['synced'] == false
      ).length;
      
      return {
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
        'pendingSyncCount': syncQueue.length,
        'localActionsCount': localActions.length,
        'unsyncedActionsCount': unsyncedActions,
        'shouldSync': _shouldSync(),
        'shouldForceSync': _shouldForceSync(),
        'nextSyncInHours': _lastSyncTime != null ? 
          (2 - DateTime.now().difference(_lastSyncTime!).inHours).clamp(0, 2) : 0,
      };
    } catch (e) {
      print('❌ AdherenceService: Error getting sync status: $e');
      return {
        'lastSyncTime': null,
        'pendingSyncCount': 0,
        'localActionsCount': 0,
        'unsyncedActionsCount': 0,
        'shouldSync': true,
        'shouldForceSync': true,
        'nextSyncInHours': 0,
      };
    }
  }
  
  // Get pending sync actions count
  Future<int> getPendingSyncCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncQueueJson = prefs.getString('adherence_sync_queue') ?? '[]';
      
      List<dynamic> syncQueue = [];
      try {
        syncQueue = jsonDecode(syncQueueJson);
        if (syncQueue is! List) syncQueue = [];
      } catch (e) {
        return 0;
      }
      
      return syncQueue.length;
    } catch (e) {
      return 0;
    }
  }

  // Update medicine action (local only for now)
  Future<void> updateMedicineAction({
    required String userId,
    required String actionId,
    required String action,
    String? notes,
  }) async {
    try {
      await _initializeCache();
      
      final prefs = await SharedPreferences.getInstance();
      final localActionsJson = prefs.getString('adherence_local_actions') ?? '[]';
      
      List<dynamic> localActions = [];
      try {
        localActions = jsonDecode(localActionsJson);
        if (localActions is! List) localActions = [];
      } catch (e) {
        return;
      }
      
      // Find and update the action
      for (int i = 0; i < localActions.length; i++) {
        if (localActions[i]['id'] == actionId) {
          localActions[i]['action'] = action;
          localActions[i]['notes'] = notes;
          localActions[i]['updatedAt'] = DateTime.now().toIso8601String();
          localActions[i]['synced'] = false; // Mark for re-sync
          break;
        }
      }
      
      // Save updated actions
      await prefs.setString('adherence_local_actions', jsonEncode(localActions));
      
      print('✅ AdherenceService: Medicine action updated locally');
    } catch (e) {
      print('❌ AdherenceService: Error updating medicine action: $e');
      throw Exception('Failed to update medicine action: $e');
    }
  }

  // Delete medicine action (local only for now)
  Future<void> deleteMedicineAction({
    required String userId,
    required String actionId,
  }) async {
    try {
      await _initializeCache();
      
      final prefs = await SharedPreferences.getInstance();
      final localActionsJson = prefs.getString('adherence_local_actions') ?? '[]';
      
      List<dynamic> localActions = [];
      try {
        localActions = jsonDecode(localActionsJson);
        if (localActions is! List) localActions = [];
      } catch (e) {
        return;
      }
      
      // Remove the action
      localActions.removeWhere((action) => action['id'] == actionId);
      
      // Save updated actions
      await prefs.setString('adherence_local_actions', jsonEncode(localActions));
      
      print('✅ AdherenceService: Medicine action deleted locally');
    } catch (e) {
      print('❌ AdherenceService: Error deleting medicine action: $e');
      throw Exception('Failed to delete medicine action: $e');
    }
  }

  // Export adherence data for backup
  Future<Map<String, dynamic>> exportAdherenceData({
    required String userId,
    String? startDate,
    String? endDate,
  }) async {
    try {
      final adherenceData = await getAdherenceData(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
      );

      return {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': userId,
        'period': {
          'startDate': startDate,
          'endDate': endDate,
        },
        'totalRecords': adherenceData.length,
        'data': adherenceData,
      };
    } catch (e) {
      print('❌ AdherenceService: Error exporting adherence data: $e');
      throw Exception('Failed to export adherence data: $e');
    }
  }
} 