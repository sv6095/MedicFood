import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/medicine_action_service.dart';
import '../services/adherence_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/auth_service.dart'; // Fixed import path
import 'package:provider/provider.dart'; // Added import for Provider

// Loading state enum for tracking data operations
enum LoadingState { idle, loading, loaded, error }

// Extension to compare dates without time
extension DateOnlyCompare on DateTime {
  bool isSameDate(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}

class AdherenceTrackingScreen extends StatefulWidget {
  // Global key to access state from anywhere
  static final GlobalKey<_AdherenceTrackingScreenState> globalKey = GlobalKey<_AdherenceTrackingScreenState>();
  
  AdherenceTrackingScreen({Key? key}) : super(key: globalKey);

  @override
  State<AdherenceTrackingScreen> createState() => _AdherenceTrackingScreenState();
}

class _AdherenceTrackingScreenState extends State<AdherenceTrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MedicineActionService _medicineActionService = MedicineActionService();
  final AdherenceService _adherenceService = AdherenceService();
  
  // Debouncing for refresh calls
  DateTime? _lastRefreshTime;
  
  // Loading state management
  final ValueNotifier<LoadingState> _loadingState = ValueNotifier<LoadingState>(LoadingState.idle);
  Timer? _loadingTimeout;
  bool _isDisposed = false;
  
  // Getter for loading state
  LoadingState get loadingState => _loadingState.value;
  
  late TabController _tabController;
  
  // Overall statistics
  Map<String, dynamic> _overallStats = {};
  
  // Weekly and monthly summaries
  List<Map<String, dynamic>> _weeklySummary = [];
  List<Map<String, dynamic>> _monthlySummary = [];
  
  // Recent medicines
  List<Map<String, dynamic>> _recentMedicines = [];
  Map<String, List<Map<String, dynamic>>> _groupedRecentMedicines = {};

  // Loading state listener callback
  void _handleLoadingStateChange() {
    // Trigger UI update when loading state changes
    if (mounted && !_isDisposed) {
      setState(() {
        // State update is triggered by the ValueNotifier
        print('🔄 Adherence: Loading state changed to ${_loadingState.value}');
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Set initial loading state
    _loadingState.value = LoadingState.idle;
    
    // Add listener for loading state changes
    _loadingState.addListener(_handleLoadingStateChange);
    
    // Register as a lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize service and load data safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      print('🚀 Adherence: Post frame callback triggered');
      _initializeService();
      _loadDataSafely();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    print('🔄 Adherence: App lifecycle changed to $state');
    
    // Refresh data when app comes to foreground
    if (state == AppLifecycleState.resumed) {
      // Delay the refresh slightly to allow UI to settle
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isDisposed) {
          print('🔄 Adherence: App resumed, refreshing data');
          // Clear cache to ensure fresh data
          _medicineActionService.clearCache();
          _adherenceService.clearLocalCache();
          _loadDataSafely();
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // App is partially visible but may be in transition
      print('⏸️ Adherence: App paused, waiting for next lifecycle event');
    }
  }

  void _initializeService() {
    print('🚀 Adherence: Initializing service');
    _medicineActionService.initialize();
    
    // Clear any existing callback to avoid duplicates
    _medicineActionService.onMedicineActionReceived = null;
    
    // Set up callback with debouncing
    _medicineActionService.onMedicineActionReceived = (actionData) {
      print('📱 Adherence: Action received callback triggered with data: $actionData');
      
      // Debounce rapid refreshes
      final now = DateTime.now();
      if (_lastRefreshTime != null) {
        final timeSinceLastRefresh = now.difference(_lastRefreshTime!).inMilliseconds;
        if (timeSinceLastRefresh < 1000) { // 1 second debounce
          print('⏱️ Adherence: Debouncing refresh (${timeSinceLastRefresh}ms since last)');
          return;
        }
      }
      _lastRefreshTime = now;
      
      // Use a post-frame callback to ensure we're on the UI thread
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isDisposed) {
          // Check if we're already loading data using atomic loading state
          if (_loadingState.value == LoadingState.loading) {
            print('⚠️ Adherence: Load already in progress, scheduling follow-up refresh');
            // Schedule a follow-up refresh after the current one completes
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted && !_isDisposed && _loadingState.value != LoadingState.loading) {
                print('⏱️ Adherence: Performing delayed follow-up refresh');
                forceRefresh();
              }
            });
          } else {
            print('✅ Adherence: Refreshing data after action received');
            forceRefresh();
          }
        } else {
          print('⚠️ Adherence: Cannot refresh - widget not mounted or disposed');
        }
      });
    };
    
    print('✅ Adherence: Service initialized');
  }

  // Force a refresh with cache clearing
  void forceRefresh() {
    print('🔄 Adherence: Force refreshing data');
    
    // Clear all caches to ensure fresh data
    _medicineActionService.clearCache();
    _adherenceService.clearLocalCache();
    
    // Force refresh MedicineActionService cache
    _medicineActionService.forceRefreshCache(['all_medicine_actions']);
    
    print('🧹 Adherence: All caches cleared, loading fresh data');
    _loadDataSafely();
  }

  // Safe wrapper for data loading
  void _loadDataSafely() {
    if (_loadingState.value == LoadingState.loading) {
      print('⚠️ Adherence: Load already in progress, skipping request');
      return;
    }
    
    if (_isDisposed) {
      print('⚠️ Adherence: Widget is disposed, cannot load data');
      return;
    }
    
    if (!mounted) {
      print('⚠️ Adherence: Widget is not mounted, cannot load data');
      return;
    }
    
    print('✅ Adherence: Starting safe data loading sequence');
    
    // Use the main thread to ensure state changes are applied safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed && _loadingState.value != LoadingState.loading) {
        _loadData();
      } else {
        print('⚠️ Adherence: State changed during post frame callback, aborting load');
      }
    });
  }

  // Simplified and more robust data loading
  Future<void> _loadData() async {
    if (_loadingState.value == LoadingState.loading) {
      print('⚠️ Adherence: Already loading, skipping');
      return;
    }

    // Atomically update loading state
    _loadingState.value = LoadingState.loading;
    
    try {
      print('🔄 Adherence: Starting data load');

      // Set a global timeout
      _loadingTimeout?.cancel();
      _loadingTimeout = Timer(const Duration(seconds: 20), () {
        if (_loadingState.value == LoadingState.loading && mounted && !_isDisposed) {
          print('⚠️ Adherence: Loading timeout reached');
          _finishLoading(false);
        }
      });

      // Load all data concurrently with individual error handling
      final results = await Future.wait([
        _loadOverallStats(),
        _loadWeeklySummary(),
        _loadMonthlySummary(),
        _loadRecentMedicines(),
      ]);

      // Check if any data was loaded successfully
      final anySuccess = results.any((success) => success == true);
      
      print('📊 Adherence: Data loading completed - Overall: ${results[0]}, Weekly: ${results[1]}, Monthly: ${results[2]}, Recent: ${results[3]}');
      
      // Force UI refresh after all data is loaded
      if (mounted && !_isDisposed) {
        setState(() {});
        print('✅ Adherence: UI refreshed with new data');
      }
      
      _finishLoading(anySuccess);
      
    } catch (e) {
      print('❌ Adherence: Error in data loading: $e');
      _finishLoading(false);
    }
  }

  // Individual loading methods with proper error handling
  // Get current user ID
  Future<String> _getCurrentUserId() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userDetails != null) {
      return authService.userDetails!.id;
    }
    
    // Fallback to SharedPreferences if auth service doesn't have user details
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      throw Exception('User ID not found. Please restart the app or re-enter your name.');
    }
    return userId;
  }

  Future<bool> _loadOverallStats() async {
    try {
      final userId = await _getCurrentUserId();
      
      // Get statistics from adherence service
      final stats = await _adherenceService.getAdherenceStatistics(userId: userId);
      
      if (mounted && !_isDisposed) {
        _overallStats = stats;
        return true;
      }
    } catch (e) {
      print('❌ Adherence: Error loading overall stats: $e');
      if (mounted && !_isDisposed) {
        _overallStats = _getEmptyStatsData();
      }
    }
    return false;
  }

  Future<bool> _loadWeeklySummary() async {
    try {
      final userId = await _getCurrentUserId();
      
      // Get weekly summary from adherence service
      final weekly = await _adherenceService.getWeeklyAdherenceSummary(userId: userId);
      
      if (mounted && !_isDisposed) {
        _weeklySummary = weekly;
        print('✅ Adherence: Loaded ${weekly.length} weekly summaries');
        // Don't call setState here - let the main loading method handle it
        return weekly.isNotEmpty;
      }
    } catch (e) {
      print('❌ Adherence: Error loading weekly summary: $e');
      if (mounted && !_isDisposed) {
        _weeklySummary = [];
        // Don't call setState here - let the main loading method handle it
      }
    }
    return false;
  }

  Future<bool> _loadMonthlySummary() async {
    try {
      final userId = await _getCurrentUserId();
      
      // Get monthly summary from adherence service
      final monthly = await _adherenceService.getMonthlyAdherenceSummary(userId: userId);
      
      if (mounted && !_isDisposed) {
        _monthlySummary = monthly;
        print('✅ Adherence: Loaded ${monthly.length} monthly summaries');
        // Don't call setState here - let the main loading method handle it
        return monthly.isNotEmpty;
      }
    } catch (e) {
      print('❌ Adherence: Error loading monthly summary: $e');
      if (mounted && !_isDisposed) {
        _monthlySummary = [];
        // Don't call setState here - let the main loading method handle it
      }
    }
    return false;
  }

  Future<bool> _loadRecentMedicines() async {
    try {
      final userId = await _getCurrentUserId();
      
      // Get recent adherence data from adherence service
      final recent = await _adherenceService.getRecentAdherenceData(userId: userId, limit: 50);
      
      if (mounted && !_isDisposed) {
        _recentMedicines = recent;
        
        // Group medicines by date
        final grouped = <String, List<Map<String, dynamic>>>{};
        
        for (final medicine in recent) {
          if (medicine.containsKey('date') && 
              medicine['date'] != null && 
              medicine['date'] is String) {
            final date = medicine['date'] as String;
            grouped[date] ??= [];
            grouped[date]!.add(medicine);
          }
        }

        // Sort and limit
        final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
        final limitedGrouped = <String, List<Map<String, dynamic>>>{};
        
        for (final date in sortedDates.take(7)) {
          grouped[date]!.sort((a, b) {
            final timeA = a['time']?.toString() ?? '';
            final timeB = b['time']?.toString() ?? '';
            return timeB.compareTo(timeA);
          });
          limitedGrouped[date] = grouped[date]!;
        }
        
        _groupedRecentMedicines = limitedGrouped;
        return recent.isNotEmpty;
      }
    } catch (e) {
      print('❌ Adherence: Error loading recent medicines: $e');
      if (mounted && !_isDisposed) {
        _recentMedicines = [];
        _groupedRecentMedicines = {};
      }
    }
    return false;
  }

  // Centralized method to finish loading
  void _finishLoading(bool success) {
    // Cancel any existing timeout first
    if (_loadingTimeout != null) {
      _loadingTimeout?.cancel();
      _loadingTimeout = null;
    }
    
    // Update loading state directly without setState
    // This is atomic and thread-safe
    _loadingState.value = success ? LoadingState.loaded : LoadingState.error;
    
    // Only proceed with UI updates if widget is still valid
    if (!mounted || _isDisposed) {
      print('⚠️ Adherence: Widget no longer valid during _finishLoading');
      return;
    }
    
    // Show messages if appropriate
    try {
      // Only show messages if the widget is still mounted and active
      if (!success) {
        _showErrorMessage('Failed to load data. Pull down to refresh.');
      } else if (_recentMedicines.isEmpty && _weeklySummary.isEmpty) {
        _showMessage('No medication data found. Add medications to track adherence.');
      }
      
      print('✅ Adherence: Loading finished, success: $success');
    } catch (e) {
      print('❌ Adherence: Error in _finishLoading: $e');
    }
  }

  // Safe setState helper
  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed && _loadingState.value != LoadingState.loading) {
      setState(fn);
    }
  }

  // Helper methods for external access
  bool isDisposed() => _isDisposed;
  
  // Safe method to load data from external calls
  void safeLoadData() {
    if (mounted && !_isDisposed) {
      print('🔄 Adherence: Safe load data called from external source');
      _loadDataSafely();
    } else {
      print('⚠️ Adherence: Cannot load data - screen disposed or not mounted');
    }
  }

  @override
  void dispose() {
    print('⚠️ Adherence: Widget being disposed');
    
    _isDisposed = true;
    _loadingTimeout?.cancel();
    
    // Remove loading state listener
    _loadingState.removeListener(_handleLoadingStateChange);
    
    // Clear the callback
    _medicineActionService.onMedicineActionReceived = null;
    
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Adherence Tracking',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadingState == LoadingState.loading ? null : () {
              _medicineActionService.clearCache();
              _adherenceService.clearLocalCache();
              _loadDataSafely();
            },
            tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _medicineActionService.clearCache();
          _adherenceService.clearLocalCache();
          await _loadData();
        },
        child: loadingState == LoadingState.loading 
          ? _buildLoadingView()
          : _buildContentView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildShimmerOverallStatistics(),
        const SizedBox(height: 16),
        _buildTabBar(),
        const SizedBox(height: 16),
        SizedBox(
          height: 400,
          child: _buildShimmerWeeklyView(),
        ),
      ],
    );
  }

  Widget _buildContentView() {
    // Calculate available height for tabs
    final screenHeight = MediaQuery.of(context).size.height;
    final appBarHeight = AppBar().preferredSize.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final availableHeight = screenHeight - appBarHeight - statusBarHeight - 160 - 48 - bottomPadding - 32;
    final tabContentHeight = math.max(availableHeight, 300.0);
    
    // Check if we have any data to display
    bool hasData = _recentMedicines.isNotEmpty || _weeklySummary.isNotEmpty || _monthlySummary.isNotEmpty;
    
    if (!hasData) {
      return _buildEmptyStateView();
    }
    
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        _buildOverallStatistics(),
        const SizedBox(height: 16),
        _buildTabBar(),
        SizedBox(
          height: tabContentHeight,
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            controller: _tabController,
            children: [
              _buildWeeklyView(),
              _buildMonthlyView(),
              _buildRecentMedicinesView(),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildEmptyStateView() {
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      children: [
        _buildOverallStatistics(),
        SizedBox(height: 24),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.medication_outlined,
                size: 80,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: 16),
              Text(
                'No Adherence Data Yet',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'You haven\'t tracked any medications yet. Add medications to your schedule to start tracking your adherence.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: 40),
              OutlinedButton.icon(
                onPressed: () {
                  _medicineActionService.clearCache();
                  _adherenceService.clearLocalCache();
                  _loadDataSafely();
                },
                icon: Icon(Icons.refresh),
                label: Text('Refresh'),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverallStatistics() {
    final adherenceRate = _overallStats['adherenceRate'] ?? 0.0;
    final totalScheduled = _overallStats['totalScheduled'] ?? 0;
    final totalTaken = _overallStats['totalTaken'] ?? 0;
    final totalMissed = _overallStats['totalMissed'] ?? 0;
    final totalSkipped = _overallStats['totalSkipped'] ?? 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Overall Adherence',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${adherenceRate.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Taken', totalTaken, Colors.green),
              _buildStatItem('Missed', totalMissed, Colors.red),
              _buildStatItem('Skipped', totalSkipped, Colors.orange),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: totalScheduled > 0 ? totalTaken / totalScheduled : 0,
            backgroundColor: Colors.white.withOpacity(0.3),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getIconForLabel(label),
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value.toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  IconData _getIconForLabel(String label) {
    switch (label.toLowerCase()) {
      case 'taken':
        return Icons.check_circle;
      case 'missed':
        return Icons.cancel;
      case 'skipped':
        return Icons.pause;
      default:
        return Icons.medication;
    }
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFF1E3A8A),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey[600],
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
        tabs: const [
          Tab(text: 'Weekly'),
          Tab(text: 'Monthly'),
          Tab(text: 'Recent'),
        ],
      ),
    );
  }

  Widget _buildWeeklyView() {
    if (_weeklySummary.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No weekly adherence data available yet. Take your medicines regularly to build your adherence statistics!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    // Use a container with a specific height to prevent overflow
    return ListView.builder(
      physics: const ClampingScrollPhysics(), // Prevent conflict with parent scrolling
      shrinkWrap: true, // Only take needed space
      padding: const EdgeInsets.all(16),
      itemCount: _weeklySummary.length,
      itemBuilder: (context, index) {
        // Rest of your existing code for building weekly items
        final week = _weeklySummary[index];
        final stats = week['statistics'] as Map<String, dynamic>;
        final adherenceRate = stats['adherenceRate'] as double;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Week ${week['week']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getAdherenceColor(adherenceRate),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${adherenceRate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${week['startDate']} - ${week['endDate']}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMiniStat('Taken', stats['totalTaken'] as int, Colors.green),
                    _buildMiniStat('Missed', stats['totalMissed'] as int, Colors.red),
                    _buildMiniStat('Skipped', stats['totalSkipped'] as int, Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMonthlyView() {
    if (_monthlySummary.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No monthly adherence data available yet. Continue taking your medicines to see your monthly statistics!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(), // Prevent conflict with parent scrolling
      shrinkWrap: true, // Only take needed space
      padding: const EdgeInsets.all(16),
      itemCount: _monthlySummary.length,
      itemBuilder: (context, index) {
        // The rest of your existing monthly item building code
        final month = _monthlySummary[index];
        final stats = month['statistics'] as Map<String, dynamic>;
        final adherenceRate = stats['adherenceRate'] as double;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      month['month'] as String,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getAdherenceColor(adherenceRate),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${adherenceRate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${month['startDate']} - ${month['endDate']}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMiniStat('Taken', stats['totalTaken'] as int, Colors.green),
                    _buildMiniStat('Missed', stats['totalMissed'] as int, Colors.red),
                    _buildMiniStat('Skipped', stats['totalSkipped'] as int, Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentMedicinesView() {
    if (_recentMedicines.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'No medicine activity data available yet. Your medicine activity will appear here once you start taking medications.',
              textAlign: TextAlign.center,
              style: TextStyle(
              fontSize: 16,
                color: Colors.grey,
              ),
            ),
        ),
      );
    }

    return ListView.builder(
      physics: const ClampingScrollPhysics(), // Prevent conflict with parent scrolling
      shrinkWrap: true, // Only take needed space
      padding: const EdgeInsets.all(16),
      itemCount: _groupedRecentMedicines.length,
      itemBuilder: (context, sectionIndex) {
        final date = _groupedRecentMedicines.keys.elementAt(sectionIndex);
        final actions = _groupedRecentMedicines[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _formatDateHeading(date),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            ...actions.map((action) {
              final medicineName = action['medicineName'] as String;
              final medicineAction = action['action'] as String;
              final time = action['time']?.toString() ?? '';
              
              return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getActionColor(medicineAction),
                  child: Icon(
                      _getActionIcon(medicineAction),
                      color: Colors.white,
                    ),
                  ),
                  title: Text(medicineName),
                  subtitle: Text(time),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _getActionColor(medicineAction).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      _getActionText(medicineAction),
                      style: TextStyle(
                        color: _getActionColor(medicineAction),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              );
            }).toList(),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Widget _buildMiniStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Color _getAdherenceColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 60) return Colors.orange;
    return Colors.red;
  }

  Color _getActionColor(String action) {
    switch (action.toLowerCase()) {
      case 'taken':
        return Colors.green;
      case 'missed':
        return Colors.red;
      case 'skipped':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getActionIcon(String action) {
    switch (action.toLowerCase()) {
      case 'taken':
        return Icons.check_circle;
      case 'missed':
        return Icons.cancel;
      case 'skipped':
        return Icons.pause;
      default:
        return Icons.medication;
    }
  }

  String _getActionText(String action) {
    switch (action.toLowerCase()) {
      case 'taken':
        return 'Taken';
      case 'missed':
        return 'Missed';
      case 'skipped':
        return 'Skipped';
      default:
        return 'Unknown';
    }
  }

  String _formatDateHeading(String date) {
    try {
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final yesterday = DateFormat('yyyy-MM-dd').format(
        now.subtract(const Duration(days: 1))
      );
      
      if (date == today) {
        return 'Today';
      } else if (date == yesterday) {
        return 'Yesterday';
      } else {
        final parsedDate = DateFormat('yyyy-MM-dd').parse(date);
        return DateFormat('EEEE, MMMM d').format(parsedDate);
      }
    } catch (e) {
      print('Error formatting date heading: $e');
      return date;
    }
  }

  // Shimmer effect for the overall statistics section
  Widget _buildShimmerOverallStatistics() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Shimmer.fromColors(
        baseColor: Colors.white.withOpacity(0.2),
        highlightColor: Colors.white.withOpacity(0.4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 150,
                  height: 20,
                  color: Colors.white.withOpacity(0.5),
                ),
                Container(
                  width: 60,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildShimmerStatItem(),
                _buildShimmerStatItem(),
                _buildShimmerStatItem(),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 8,
              color: Colors.white.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  // Helper for shimmer stats
  Widget _buildShimmerStatItem() {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 60,
          height: 12,
          color: Colors.white,
        ),
      ],
    );
  }

  // Shimmer effect for weekly view
  Widget _buildShimmerWeeklyView() {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: 4, // Show 4 skeleton items
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              height: 160,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 100,
                        height: 16,
                        color: Colors.white,
                      ),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      3,
                      (i) => Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 50,
                            height: 10,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Shimmer effect for monthly view
  Widget _buildShimmerMonthlyView() {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: 3, // Show 3 skeleton items
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              height: 180,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 120,
                        height: 16,
                        color: Colors.white,
                      ),
                      Container(
                        width: 60,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 12,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(
                      3,
                      (i) => Column(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 50,
                            height: 10,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 8,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 30,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Shimmer effect for recent medicines view
  Widget _buildShimmerRecentMedicinesView() {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      itemCount: 3, // 3 sections
      itemBuilder: (context, sectionIndex) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(
                width: 150,
                height: 20,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.white,
              ),
            ),
            // 3 items per section
            ...List.generate(3, (itemIndex) => 
              Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    height: 70,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 120,
                                height: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 80,
                                height: 12,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  // Show error message with SnackBar
  void _showErrorMessage(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          duration: Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'RETRY',
            textColor: Colors.white,
            onPressed: () {
              _medicineActionService.clearCache();
              _adherenceService.clearLocalCache();
              _loadDataSafely();
            },
          ),
        ),
      );
    }
  }
  
  // Show informational message with SnackBar
  void _showMessage(String message) {
    if (mounted && !_isDisposed) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.blue.shade700,
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  // Return empty statistics data
  Map<String, dynamic> _getEmptyStatsData() {
    return {
      'adherenceRate': 0.0,
      'totalTaken': 0,
      'totalMissed': 0,
      'totalSkipped': 0,
      'totalScheduled': 0,
      'period': {
        'startDate': null,
        'endDate': null,
      },
    };
  }
}

// Create a helper method to access the screen from anywhere
Future<void> refreshAdherenceTrackingScreen() async {
  try {
    print('🔄 Global Helper: Attempting to refresh adherence tracking screen');
    final state = AdherenceTrackingScreen.globalKey.currentState;
    if (state != null) {
      // Double check if the state is still valid using the widget's own safety methods
      if (!state.isDisposed() && state.mounted) {
        print('✅ Global Helper: Safely refreshing adherence tracking screen');
        // Use the new force refresh method that clears cache
        try {
          state.forceRefresh();
        } catch (e) {
          print('⚠️ Global Helper: Error calling force refresh, falling back to safeLoadData');
          state.safeLoadData();
        }
      } else {
        print('⚠️ Global Helper: Adherence tracking screen state is not valid for refresh');
      }
    } else {
      print('⚠️ Global Helper: No adherence tracking screen state found for refresh');
    }
  } catch (e) {
    print('❌ Global Helper: Error refreshing adherence tracking screen: $e');
  }
} 