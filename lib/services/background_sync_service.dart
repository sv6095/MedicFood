import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import './adherence_service.dart';
import './medicine_service.dart';

class BackgroundSyncService {
  static final BackgroundSyncService _instance = BackgroundSyncService._internal();
  factory BackgroundSyncService() => _instance;
  BackgroundSyncService._internal();

  Timer? _syncTimer;
  bool _isInitialized = false;

  // Initialize background sync
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      print('🚀 BackgroundSyncService: Initializing automatic background sync');
      
      // Start periodic sync (every 15 minutes)
      _startPeriodicSync();
      
      // Perform initial sync check
      await _performBackgroundSync();
      
      _isInitialized = true;
      print('✅ BackgroundSyncService: Automatic background sync initialized');
    } catch (e) {
      print('❌ BackgroundSyncService: Error initializing background sync: $e');
    }
  }

  // Start periodic sync timer
  void _startPeriodicSync() {
    // Cancel existing timer if any
    _syncTimer?.cancel();
    
    // Start new timer (15 minutes interval for more frequent syncs)
    _syncTimer = Timer.periodic(Duration(minutes: 15), (timer) async {
      await _performBackgroundSync();
    });
    
    print('⏰ BackgroundSyncService: Periodic sync timer started (15 min intervals)');
  }

  // Perform background sync
  Future<void> _performBackgroundSync() async {
    try {
      print('🔄 BackgroundSyncService: Starting background sync');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId == null || userId.isEmpty) {
        print('⚠️ BackgroundSyncService: No user ID found, skipping sync');
        return;
      }
      
      final adherenceService = AdherenceService();
      final medicineService = MedicineService();
      
      // Always try to sync - let the adherence service decide if it's needed
      print('📊 BackgroundSyncService: Checking for sync opportunities...');
      await adherenceService.autoSync(userId: userId);
      
      // Sync local medicine updates to Firebase
      print('💊 BackgroundSyncService: Syncing local medicine updates...');
      await medicineService.syncLocalUpdatesToFirebase(userId);
      
    } catch (e) {
      print('❌ BackgroundSyncService: Error during background sync: $e');
    }
  }

  // Automatic sync trigger (called by timer)
  Future<void> triggerSync() async {
    try {
      print('🔄 BackgroundSyncService: Automatic sync triggered');
      await _performBackgroundSync();
    } catch (e) {
      print('❌ BackgroundSyncService: Error in automatic sync: $e');
    }
  }

  // Sync on app close
  Future<void> syncOnAppClose() async {
    try {
      print('🔄 BackgroundSyncService: Syncing on app close');
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      
      if (userId != null && userId.isNotEmpty) {
        final adherenceService = AdherenceService();
        final medicineService = MedicineService();
        
        await adherenceService.syncOnAppClose(userId: userId);
        await medicineService.syncLocalUpdatesToFirebase(userId);
      }
    } catch (e) {
      print('❌ BackgroundSyncService: Error syncing on app close: $e');
    }
  }

  // Stop background sync
  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isInitialized = false;
    print('⏹️ BackgroundSyncService: Background sync stopped');
  }

  // Get sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final adherenceService = AdherenceService();
      final status = await adherenceService.getSyncStatus();
      
      return {
        ...status,
        'isInitialized': _isInitialized,
        'hasActiveTimer': _syncTimer != null,
      };
    } catch (e) {
      return {
        'isInitialized': _isInitialized,
        'hasActiveTimer': _syncTimer != null,
        'error': e.toString(),
      };
    }
  }

  // Dispose resources
  void dispose() {
    stop();
  }
} 