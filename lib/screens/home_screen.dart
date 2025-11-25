import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/auth_service.dart';
import '../services/medicine_service.dart';
import '../services/notification_service.dart';
import 'medicine_search_screen.dart';
import 'prescription_scanner_screen.dart';
import 'caretaker_screen.dart';
import 'settings_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'card_detail_screen.dart';
import '../utils/timing_utils.dart';
import '../utils/duration_helper.dart';
import '../services/notification_navigation_service.dart';
import 'package:shimmer/shimmer.dart';
import 'package:system_alert_window/system_alert_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:material_symbols_icons/symbols.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class HomeScreen extends StatefulWidget {
  HomeScreen();

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  int _selectedIndex = 0;
  static const String FIRST_LAUNCH_KEY = 'is_first_launch';
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final GlobalKey<_HomeContentState> _homeContentKey = GlobalKey<_HomeContentState>();

  bool _isInitializing = true;
  bool _isNameSetupComplete = false;
  bool _isUiLoaded = false;
  String _savedName = '';
  late StreamSubscription _navigationSubscription;
  late StreamSubscription _snoozeSubscription;
  final NotificationService _notificationService = NotificationService();

  // Add a selected date variable
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _animationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _initializeApp();

    _navigationSubscription = NotificationNavigationService()
        .navigationStream
        .listen((data) {
      _handleBackgroundNotification(data);
    });

    _snoozeSubscription = NotificationService.notificationStream.listen((event) {
      if (event['type'] == 'snooze' && mounted) {
        _handleSnooze(event['data']);
      }
    });
  }

  // Method to refresh the user name from SharedPreferences
  Future<void> refreshUserName() async {
    await _loadUserNameFromPrefs();
  }

  // Method to force reload name from Firebase
  Future<void> forceReloadNameFromFirebase() async {
    try {
      print('🔄 Force reloading name from Firebase...');
      final authService = Provider.of<AuthService>(context, listen: false);
      final prefs = await SharedPreferences.getInstance();
      
      if (authService.isAuthenticated && authService.userDetails != null) {
        final userId = authService.userDetails!.id;
        print('👤 Reloading for user: $userId');
        
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        
        print('🔥 Firebase doc exists: ${doc.exists}');
        if (doc.exists && doc.data()?['name'] != null) {
          final savedName = doc.data()!['name'] as String;
          // Save to SharedPreferences
          await prefs.setString('name_$userId', savedName);
          // Update UI
          setState(() {
            _savedName = savedName;
            _isNameSetupComplete = true;
          });
          // Update auth service
          await authService.updateUserName(savedName);
          print('✅ Force reloaded name: $savedName');
        } else {
          print('❌ No name found in Firebase during force reload');
        }
      }
    } catch (e) {
      print('❌ Error during force reload: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh name when dependencies change (e.g., when returning from settings)
    // Only refresh if we're on the home tab to avoid unnecessary calls
    if (_selectedIndex == 0) {
      _loadUserNameFromPrefs();
    }
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh name when widget is updated
    if (_selectedIndex == 0) {
      _loadUserNameFromPrefs();
    }
  }



  Future<void> _initializeApp() async {
    try {
      print('🚀 Starting app initialization...');
      // Run initialization in parallel to avoid waiting for each step
      _animationController.forward();
      setState(() {
        _isUiLoaded = true;
        _isInitializing = false;
      });
      
      // Initialize notifications in the background
      Future.microtask(() async {
        await _notificationService.initialize();
      });
      
      // Add a small delay to ensure authentication state is ready
      await Future.delayed(Duration(milliseconds: 500));
      
      // Load user data sequentially to avoid race conditions
      await _loadUserNameFromPrefs();
      await _checkFirstLaunch();
      
      // Add a longer delay and try again if name is still empty
      if (_savedName.isEmpty) {
        print('⏰ Name still empty, waiting 2 seconds and trying again...');
        await Future.delayed(Duration(seconds: 2));
        await forceReloadNameFromFirebase();
      }
      
      // Check permissions after UI is loaded
      _startPermissionFlowIfReady();
      print('✅ App initialization completed');
    } catch (e, stack) {
      print('❌ Error during app initialization: $e\n$stack');
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }
  
  // New method to load user name from SharedPreferences
  Future<void> _loadUserNameFromPrefs() async {
    try {
      print('🔍 Starting _loadUserNameFromPrefs...');
      final prefs = await SharedPreferences.getInstance();
      final authService = Provider.of<AuthService>(context, listen: false);
      
      print('🔐 Auth status: ${authService.isAuthenticated}, User: ${authService.userDetails?.id ?? 'none'}');
      
      String? savedName;
      
      if (authService.isAuthenticated && authService.userDetails != null) {
        // For authenticated users, load per user ID
        final userId = authService.userDetails!.id;
        print('👤 Loading name for authenticated user: $userId');
        savedName = prefs.getString('name_$userId');
        print('📱 SharedPreferences name_$userId: $savedName');
        
        // If no name in SharedPreferences, try to load from Firebase
        if (savedName == null || savedName.isEmpty) {
          print('☁️ No name in SharedPreferences, checking Firebase...');
          try {
            final doc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
            
            print('🔥 Firebase doc exists: ${doc.exists}');
            if (doc.exists && doc.data()?['name'] != null) {
              savedName = doc.data()!['name'] as String;
              // Save to SharedPreferences for future use
              await prefs.setString('name_$userId', savedName);
              print('✅ Loaded name from Firebase: $savedName');
            } else {
              print('❌ No name found in Firebase');
            }
          } catch (e) {
            print('❌ Error loading name from Firebase: $e');
          }
        } else {
          print('✅ Found name in SharedPreferences: $savedName');
        }
      } else {
        print('👤 Loading name for non-authenticated user...');
        // For non-authenticated users, use the old approach
        savedName = prefs.getString('name');
        print('📱 SharedPreferences name: $savedName');
        
        if (savedName != null && savedName.isNotEmpty) {
          // Ensure we have a unique user ID
          String? userId = prefs.getString('user_id');
          if (userId == null || userId.isEmpty || userId == 'default_user') {
            // Generate a unique ID using timestamp and random number
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final random = DateTime.now().microsecond;
            userId = 'local_user_${timestamp}_$random';
            await prefs.setString('user_id', userId);
            print('🆔 Generated unique user ID during load: $userId');
          }
        }
      }
      
      if (savedName != null && savedName.isNotEmpty) {
        print('✅ Name loaded successfully in _loadUserNameFromPrefs: $savedName');
        setState(() {
          _savedName = savedName!;
        });
        print('🔄 Updated _savedName state to: $_savedName');
        // Always update the auth service with the loaded name to ensure consistency
        if (authService.userDetails != null) {
          await authService.updateUserName(savedName);
          print('🔄 Updated auth service with name: $savedName');
        }
      } else {
        print('⚠️ No name found in _loadUserNameFromPrefs - showing dialog will be needed');
      }
    } catch (e) {
      print('❌ Error in _loadUserNameFromPrefs: $e');
    }
  }

  Future<void> _checkFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    final authService = Provider.of<AuthService>(context, listen: false);
    
    // Check if user is authenticated
    if (authService.isAuthenticated && authService.userDetails != null) {
      // For authenticated users, check if they need name setup
      final needsSetup = await authService.needsNameSetup();
      final userId = authService.userDetails!.id;
      
      // Load name from SharedPreferences or Firebase
      String? savedName = prefs.getString('name_$userId');
      
      // If no name in SharedPreferences, try to load from Firebase
      if (savedName == null || savedName.isEmpty) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();
          
          if (doc.exists && doc.data()?['name'] != null) {
            savedName = doc.data()!['name'] as String;
            // Save to SharedPreferences for future use
            await prefs.setString('name_$userId', savedName);
            print('Loaded name from Firebase in _checkFirstLaunch: $savedName');
          }
        } catch (e) {
          print('Error loading name from Firebase in _checkFirstLaunch: $e');
        }
      }
      
      if (savedName != null && savedName.isNotEmpty) {
        print('✅ Name loaded successfully in _checkFirstLaunch: $savedName');
        setState(() {
          _isNameSetupComplete = true;
          _savedName = savedName!; // Use null assertion since we've already checked for null
        });
        
        // Always update the auth service with the saved name to ensure consistency
        await authService.updateUserName(savedName);
      } else {
        print('⚠️ No name found in _checkFirstLaunch');
      }
      
      // Show name dialog if user needs name setup
      if (needsSetup) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showNameDialog();
        });
      }
    } else {
      // For non-authenticated users, use the old logic
      final isFirstLaunch = prefs.getBool(FIRST_LAUNCH_KEY) ?? true;
      final savedName = prefs.getString('name');
      final userId = prefs.getString('user_id');
      
      // Check if name setup is completed for non-authenticated users
      bool nameSetupCompleted = false;
      if (userId != null && userId.isNotEmpty) {
        nameSetupCompleted = prefs.getBool('name_setup_completed_$userId') ?? false;
      }
      
      if (savedName != null && savedName.isNotEmpty) {
        setState(() {
          _isNameSetupComplete = true;
          _savedName = savedName!; // Use null assertion since we've already checked for null
        });
      }
      
      // Show name dialog if it's first launch and no name is saved, or if name setup is not completed
      if ((isFirstLaunch && (savedName == null || savedName.isEmpty)) || !nameSetupCompleted) {
        if (isFirstLaunch) {
          await prefs.setBool(FIRST_LAUNCH_KEY, false);
        }
        if (savedName == null || savedName.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showNameDialog();
          });
        }
      }
    }
  }

  void _showNameDialog({bool isEditing = false}) {
    final prefsFuture = SharedPreferences.getInstance();
    final authService = Provider.of<AuthService>(context, listen: false);
    String name = _savedName.isNotEmpty ? _savedName : '';
    print('📝 Showing name dialog with current name: "$name" (isEditing: $isEditing)');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          titlePadding: EdgeInsets.fromLTRB(24, 24, 24, 8),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.waving_hand, color: Colors.orange, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  isEditing 
                    ? 'Edit Your Name' 
                    : (authService.isAuthenticated ? 'Complete Your Profile' : 'Welcome to MedicFood!'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEditing
                            ? 'Update your name to personalize your experience.'
                            : (authService.isAuthenticated 
                                ? 'Please tell us your preferred name so we can personalize your experience.'
                                : 'Please tell us your name so we can personalize your experience.'),
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            height: 1.4,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                TextField(
                  controller: TextEditingController(text: name),
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Your Name',
                    hintText: 'Enter your name',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                  onChanged: (value) {
                    name = value;
                  },
                  onSubmitted: (value) async {
                    if (value.trim().isNotEmpty) {
                      name = value;
                      final prefs = await prefsFuture;
                      _saveNameAndComplete(prefs, name, isEditing: isEditing);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (name.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Please enter your name'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                final prefs = await prefsFuture;
                _saveNameAndComplete(prefs, name, isEditing: isEditing);
              },
              child: Text(isEditing ? 'Update' : 'Continue'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveNameAndComplete(SharedPreferences prefs, String name, {bool isEditing = false}) async {
  final trimmedName = name.trim();
  if (trimmedName.isNotEmpty) {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Determine the user ID and save name accordingly
      if (authService.isAuthenticated && authService.userDetails != null) {
        // For authenticated users, save per user ID
        final userId = authService.userDetails!.id;
        await prefs.setString('name_$userId', trimmedName);
        await prefs.setBool('name_setup_completed_$userId', true);
        print('Saved name for authenticated user $userId: $trimmedName');
        
        // Update local state
        setState(() {
          _savedName = trimmedName;
        });
      } else {
        // For non-authenticated users, use the old approach
        await prefs.setString('name', trimmedName);
        
        // Generate a unique user ID for non-authenticated users
        String? userId = prefs.getString('user_id');
        if (userId == null || userId.isEmpty || userId == 'default_user') {
          // Generate a unique ID using timestamp and random number
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final random = DateTime.now().microsecond;
          userId = 'local_user_${timestamp}_$random';
          await prefs.setString('user_id', userId);
          print('Generated unique user ID: $userId');
        }
        
        // Set name setup as completed for non-authenticated users too
        await prefs.setBool('name_setup_completed_$userId', true);
        print('Saved name for non-authenticated user $userId: $trimmedName');
      }
      
      // Update the auth service
      if (authService.userDetails != null) {
        await authService.updateUserName(trimmedName);
      }
      
      if (mounted) {
        // Close the name dialog first
        Navigator.of(context).pop();
        
        // Update state immediately
        setState(() {
          _isNameSetupComplete = true;
          _savedName = trimmedName;
        });
        
        // Show confirmation
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing 
              ? 'Name updated to $trimmedName!' 
              : 'Welcome, $trimmedName! Setting up your experience...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        
        // Add a delay before starting permission flow to ensure UI is stable
        await Future.delayed(Duration(milliseconds: 1000));
        
        if (mounted) {
          _startPermissionFlowIfReady();
        }
      }
    } catch (e) {
      print('Error saving name: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving name. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

  void _startPermissionFlowIfReady() {
  if (_isUiLoaded && _isNameSetupComplete && mounted) {
    // Always check permissions when app is ready, regardless of previous requests
    Future.delayed(Duration(milliseconds: 1500), () {
      if (mounted) {
        _checkPermissionsAfterSetup();
      }
    });
  }
}

  Future<void> _checkPermissionsAfterSetup() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (!authService.isAuthenticated) return;

      final notificationPermission = await Permission.notification.isGranted;
      final exactAlarmPermission = await Permission.scheduleExactAlarm.isGranted;
      final overlay = await _notificationService.isOverlayPermissionGranted();
      
      final permissions = {
        'notifications': notificationPermission,
        'exact_alarms': exactAlarmPermission,
        'overlay': overlay,
        'all_granted': notificationPermission && exactAlarmPermission && overlay,
      };
      
      // Always show permission dialog if any permission is not granted
      if (!permissions['all_granted']!) {
        _showComprehensivePermissionDialog(permissions);
      }
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }

  void _showComprehensivePermissionDialog(Map<String, bool> permissions) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.security, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Essential Permissions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                margin: EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'MedicFood needs these permissions to provide reliable medication reminders.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade800,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              _buildPermissionItem(
                Icons.notifications_active,
                'Notifications',
                'Essential for medication reminders and alerts',
                permissions['notifications']!,
                Colors.blue,
              ),
              
              _buildPermissionItem(
                Icons.alarm_add,
                'Exact Alarms',
                'Ensures precise timing for critical medications',
                permissions['exact_alarms']!,
                Colors.red,
              ),
              
              _buildPermissionItem(
                Icons.layers,
                'Display Over Apps',
                'Shows full-screen alerts even when phone is locked',
                permissions['overlay']!,
                Colors.purple,
              ),
              
              Container(
                padding: EdgeInsets.all(16),
                margin: EdgeInsets.only(top: 24),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.orange, size: 20),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Without these permissions, you may miss important medication reminders.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPermissionDeniedWarning();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey.shade600,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermissionsWithGuidance();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text('Grant Permissions'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(IconData icon, String title, String description, bool granted, Color color) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: granted ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: granted ? Colors.green.shade200 : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              granted ? Icons.check_circle : Icons.cancel,
                              color: granted ? Colors.green : Colors.red,
                              size: 14,
                            ),
                            SizedBox(width: 6),
                            Text(
                              granted ? 'Granted' : 'Required',
                              style: TextStyle(
                                color: granted ? Colors.green.shade700 : Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestPermissionsWithGuidance() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Requesting Permissions',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Please allow all permissions in the system dialogs that appear.',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Text(
              'This may open several permission screens.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    try {
      final hasNotificationPermission = await Permission.notification.request().isGranted;
      final hasExactAlarmPermission = await Permission.scheduleExactAlarm.request().isGranted;
      
      if (mounted) {
        Navigator.pop(context);
      }
      
      bool hasOverlayPermission = false;
      
      bool userAgreedToOverlay = await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.layers, color: Colors.purple, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Critical Permission Required',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.medication, color: Colors.purple, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Display Over Other Apps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'This permission allows MedicFood to show critical medication alerts even when your phone is locked or when you\'re using other apps.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Without this permission, you may miss life-critical medication reminders.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.orange.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
              ),
              child: Text('Skip for Now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: Text('Grant Permission'),
            ),
          ],
        ),
      ) ?? false;
      
      if (userAgreedToOverlay) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Processing...',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: Text('Requesting display overlay permission...'),
            ),
          );
        }
        
        try {
          hasOverlayPermission = await _notificationService.requestDisplayOverOtherAppsPermission();
          
          if (mounted) {
            Navigator.pop(context);
          }
          
          if (!hasOverlayPermission) {
            bool shouldOpenSettings = await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blue, size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Manual Permission Setup',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.touch_app, color: Colors.blue, size: 40),
                          SizedBox(height: 12),
                          Text(
                            'Please enable manually:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '1. Find "MedicFood" in the app list\n2. Toggle "Allow display over other apps" ON\n3. Return to this app',
                            textAlign: TextAlign.left,
                            style: TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Skip'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text('Open Settings'),
                  ),
                ],
              ),
            ) ?? false;
            
            if (shouldOpenSettings) {
              await _notificationService.openDisplayOverOtherAppsSettings();
              await Future.delayed(Duration(seconds: 3));
              hasOverlayPermission = await _notificationService.isOverlayPermissionGranted();
              
              if (mounted && hasOverlayPermission) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Display overlay permission granted!',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          }
          
        } catch (e, stack) {
          if (mounted) {
            Navigator.pop(context);
          }
          
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Row(
                  children: [
                    Icon(Icons.error, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Permission Error',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                content: Text('Error requesting overlay permission. Please try enabling it manually in Settings.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('OK'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _notificationService.openDisplayOverOtherAppsSettings();
                    },
                    child: Text('Open Settings'),
                  ),
                ],
              ),
            );
          }
        }
      }
      
      final finalNotificationStatus = await Permission.notification.isGranted;
      final finalExactAlarmStatus = await Permission.scheduleExactAlarm.isGranted;
      final finalOverlayStatus = await _notificationService.isOverlayPermissionGranted();
      
      final permissions = {
        'notifications': finalNotificationStatus,
        'exact_alarms': finalExactAlarmStatus,
        'overlay': finalOverlayStatus,
        'all_granted': finalNotificationStatus && finalExactAlarmStatus && finalOverlayStatus,
      };

      if (permissions['all_granted']!) {
        _showSuccessDialog();
      } else {
        _showPartialPermissionDialog(permissions);
      }
      
    } catch (e, stack) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        _showErrorDialog('Permission request failed: $e');
      }
    }
  }

  void _showPartialPermissionDialog(Map<String, bool> permissions) {
    List<String> denied = permissions.entries
        .where((e) => e.key != 'all_granted' && !e.value)
        .map((e) => e.key.replaceAll('_', ' ').toUpperCase())
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Incomplete Setup',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The following permissions are still needed:',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            SizedBox(height: 16),
            ...denied.map((perm) => Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.radio_button_unchecked, color: Colors.red, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      perm,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            )),
            SizedBox(height: 24),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'You can grant these permissions later in Settings > Notifications.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue.shade700,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('Continue Anyway'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermissionsWithGuidance();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text('Try Again'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'All Set!',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'All permissions granted successfully!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'You\'ll receive reliable medication reminders.',
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.4,
                fontSize: 14,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text('Great!'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 16),
        title: Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Icon(Icons.error, color: Colors.red, size: 28),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Permission Error',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        content: Text(
          'Error requesting permissions: $error',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _requestPermissionsWithGuidance();
            },
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Some features may not work without permissions. You can enable them later in Settings.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange.shade700,
        duration: Duration(seconds: 6),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        action: SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _selectedIndex = 4;
            });
          },
        ),
      ),
    );
  }

  Widget _getCurrentScreen() {
    switch (_selectedIndex) {
      case 0:
        return HomeContent(
          key: _homeContentKey,
          onNavigateToDetail: _navigateToCardDetail,
          selectedDate: _selectedDate, // Pass the selected date
          onDateSelected: (date) {
            setState(() {
              _selectedDate = date;
            });
          },
          savedName: _savedName,
          onNameUpdated: (newName) {
            setState(() {
              _savedName = newName;
            });
          },
        );
      case 1:
        return MedicineSearchScreen();
      case 2:
        return PrescriptionScannerScreen(onPrescriptionScanned: _handlePrescriptionScanned);
      case 3:
        return PatientsScreen();
      case 4:
        return SettingsScreen(
          onNameUpdated: (newName) {
            setState(() {
              _savedName = newName;
            });
          },
        );
      default:
        return HomeContent(
          key: _homeContentKey,
          onNavigateToDetail: _navigateToCardDetail,
          selectedDate: _selectedDate, // Pass the selected date
          onDateSelected: (date) {
            setState(() {
              _selectedDate = date;
            });
          },
          savedName: _savedName,
          onNameUpdated: (newName) {
            setState(() {
              _savedName = newName;
            });
          },
        );
    }
  }

  void _navigateToCardDetail(Map<String, dynamic> medicineData) {
    List<String> defaultTimes = _getDefaultTimesForFrequency(
      medicineData['mappedTiming'] ?? medicineData['timing'] ?? '', 
      medicineData['mappedFrequency'] ?? medicineData['frequency'] ?? 'Once Daily'
    );
    
    // If scheduleDate is not provided, use the currently selected date
    String scheduleDate = medicineData['scheduleDate'] ?? 
                         DateFormat('yyyy-MM-dd').format(_selectedDate);

    final completeData = {
      ...medicineData,
      'name': medicineData['name'] ?? '',
      'dosage': medicineData['dosage'] ?? '',
      'time': defaultTimes.join(', '),
      'timing': medicineData['mappedTiming'] ?? medicineData['timing'] ?? '',
      'type': medicineData['type'] ?? 'Tablet',
      'frequency': medicineData['mappedFrequency'] ?? medicineData['frequency'] ?? 'Once Daily',
      'instructions': medicineData['instructions'] ?? '',
      'foodInstructions': medicineData['mappedFoodInstructions'] ?? medicineData['foodInstructions'] ?? '',
      'isFromPrescription': medicineData['isFromPrescription'] ?? false,
      'prescriptionData': medicineData['prescriptionData'],
      'id': medicineData['id'],
      'isValidated': medicineData['isValidated'] ?? false,
      'scheduleDate': scheduleDate,
      'duration': medicineData['duration'] ?? '', // <-- Added
    };

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CardDetailScreen(
          medicineName: completeData['name'],
          dosage: completeData['dosage'],
          time: completeData['time'],
          timing: completeData['timing'],
          isFromPrescription: completeData['isFromPrescription'],
          prescriptionData: completeData['prescriptionData'],
          medicineId: completeData['id'],
          type: completeData['type'],
          frequency: completeData['frequency'],
          instructions: completeData['instructions'],
          foodInstructions: completeData['foodInstructions'],
          isValidated: completeData['isValidated'],
          scheduleDate: completeData['scheduleDate'],
          duration: completeData['duration'], // <-- Added
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: FadeTransition(
              opacity: animation,
              child: child,
            ),
          );
        },
        transitionDuration: Duration(milliseconds: 400),
      ),
    ).then((result) {
      if (result == true) {
        setState(() {
          _selectedIndex = 0;
        });
        // Add a small delay to ensure the database update has propagated
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _reloadHomeContent();
          }
        });
      } else if (result is Map<String, dynamic> && result['action'] == 'updated') {
        // Handle prescription medicine updates
        setState(() {
          _selectedIndex = 0;
        });
        // Add a small delay to ensure the database update has propagated
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _reloadHomeContent();
          }
        });
      }
    });
  }

  void _reloadHomeContent() {
  if (_homeContentKey.currentState != null) {
    print('🔄 Reloading home content...');
    
    // Reset animation before loading data
    _homeContentKey.currentState!._cardAnimationController.reset();
    
    // Force refresh the StreamBuilder by updating trigger field
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userDetails != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(authService.userDetails!.id)
          .update({
            'medicationUpdateTrigger': FieldValue.serverTimestamp(),
          }).then((_) {
            print('✅ Updated trigger field');
          }).catchError((e) {
            print('❌ Error updating trigger: $e');
          });
    }
    
    // Also call _loadMedicineData for immediate refresh
    _homeContentKey.currentState!._loadMedicineData().then((_) {
      if (_homeContentKey.currentState != null && _homeContentKey.currentState!.mounted) {
        _homeContentKey.currentState!._cardAnimationController.forward();
        
        // Also reload calendar dates
        final calendarCardState = _homeContentKey.currentState!.context
            .findAncestorStateOfType<_CalendarCardState>();
        if (calendarCardState != null) {
          calendarCardState._loadMedicineDates();
        }
      }
    });
    
    // Force a setState to trigger rebuild
    setState(() {});
  }
}

  List<String> _getDefaultTimesForFrequency(String timing, String frequency) {
    // Use TimingUtils to parse frequency and generate times
    final intervalHours = TimingUtils.parseFrequencyToHours(frequency);
    
    if (intervalHours == null) {
      // For invalid frequency, return default time
      return ['08:00 AM'];
    }
    
    if (intervalHours >= 24) {
      // For daily or longer intervals, return single time
      return ['08:00 AM'];
    }
    
    // For sub-daily intervals, generate times based on frequency
    final times = TimingUtils.generateTimesFromFrequency(frequency);
    // Convert to 12-hour format to match medicine key generation
    final formattedTimes = times.map((time) {
      final hour = time.hour;
      final minute = time.minute;
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      return '${displayHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    }).toList();
    print('🕐 Generated times for frequency "$frequency": $formattedTimes');
    return formattedTimes;
  }

  void _handlePrescriptionScanned(Map<String, dynamic> prescriptionData) {
    if (prescriptionData['medicines'] != null && prescriptionData['medicines'].isNotEmpty) {
      final List<dynamic> medicines = prescriptionData['medicines'];
      for (var medicine in medicines) {
        final mappedTiming = TimingUtils.mapTimingFromPrescription(medicine['timing'] ?? '');
        final mappedFrequency = TimingUtils.mapFrequencyFromPrescription(medicine['timing'] ?? '');
        final mappedFoodInstructions = TimingUtils.mapFoodInstructionsFromPrescription(medicine['instructions'] ?? '');
        final defaultTimes = TimingUtils.convertTimingToTime(mappedTiming);

        String medicineType = medicine['form'] ?? medicine['type'] ?? 'Tablet';
        medicineType = medicineType[0].toUpperCase() + medicineType.substring(1).toLowerCase();

        medicine.addAll({
          'mappedTiming': mappedTiming,
          'mappedFrequency': mappedFrequency,
          'mappedTime': defaultTimes,
          'mappedFoodInstructions': mappedFoodInstructions,
          'type': medicineType,
          'validated': medicine['validated'] ?? false,
        });
      }
      _showPrescriptionReviewDialog(prescriptionData);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No medicines found in prescription'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _showPrescriptionReviewDialog(Map<String, dynamic> prescriptionData) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => PrescriptionReviewDialog(
          prescriptionData: prescriptionData,
          onSaveAll: () {
            Navigator.of(context).pop();
            _saveAllPrescriptionMedicines(prescriptionData);
          },
          onEditIndividual: (medicine) async {
            Navigator.of(context).pop();
            await Future.delayed(Duration(milliseconds: 200));
            
            final result = await _navigateToCardDetailForPrescription(medicine, prescriptionData);
            
            if (result != null && result is Map<String, dynamic>) {
              if (result['action'] == 'updated' || result['action'] == 'back') {
                final updatedMedicine = result['medicineData'];
                final originalName = result['originalName'];
                
                final medicines = prescriptionData['medicines'] as List;
                final index = medicines.indexWhere((m) => m['name'] == originalName);
                if (index != -1) {
                  medicines[index] = <String, dynamic>{...medicines[index], ...updatedMedicine};
                }
                
                await Future.delayed(Duration(milliseconds: 100));
                if (mounted) {
                  _showPrescriptionReviewDialog(prescriptionData);
                }
              }
            } else {
              await Future.delayed(Duration(milliseconds: 100));
              if (mounted) {
                _showPrescriptionReviewDialog(prescriptionData);
              }
            }
          },
        ),
      ),
    );
  }

  Future<dynamic> _navigateToCardDetailForPrescription(
    Map<String, dynamic> medicine, 
    Map<String, dynamic> prescriptionData
  ) async {
    final originalName = medicine['name'];
    final completeData = {
      ...medicine,
      'isFromPrescription': true,
      'prescriptionData': prescriptionData,
      'timing': medicine['mappedTiming'] ?? medicine['timing'],
      'frequency': medicine['mappedFrequency'] ?? medicine['frequency'],
      'originalName': originalName,
    };

    return await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => CardDetailScreen(
          medicineName: completeData['name'],
          dosage: completeData['dosage'],
          time: completeData['time'],
          timing: completeData['timing'],
          isFromPrescription: completeData['isFromPrescription'],
          prescriptionData: completeData['prescriptionData'],
          medicineId: completeData['id'],
          type: completeData['type'] ?? 'Tablet',
          frequency: completeData['frequency'],
          instructions: completeData['instructions'] ?? '',
          foodInstructions: completeData['foodInstructions'],
          isValidated: completeData['isValidated'] ?? false,
          scheduleDate: completeData['scheduleDate'],
          duration: completeData['duration'] ?? '', // <-- Added
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(begin: begin, end: end).chain(
            CurveTween(curve: curve),
          );

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 400),
      ),
    );
  }

  void _saveAllPrescriptionMedicines(Map<String, dynamic> prescriptionData) async {
  try {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.userDetails == null) return;

    final medicineService = MedicineService();
    final medicines = prescriptionData['medicines'] as List;
    
    // Create a list to store all medicine data
    List<Map<String, dynamic>> allMedicineData = [];
    
    // ALWAYS start from today (now), not from selected date
    DateTime startDate = DateTime.now();
    print('📅 Saving medicines starting from TODAY: ${DateFormat('yyyy-MM-dd').format(startDate)}');
    
    // For each medicine, create entries based on the duration from prescription
    for (var medicine in medicines) {
      // Parse duration from prescription
      String durationText = medicine['duration'] ?? '';
      int? durationDays = DurationHelper.parseDurationToDays(durationText);
      
      // Default to 1 day if duration cannot be parsed or is indefinite
      if (durationDays == null || durationDays <= 0) {
        durationDays = 1;
        print('⚠️ Could not parse duration for ${medicine['name']}, defaulting to 1 day');
      }
      
      print('📅 Medicine: ${medicine['name']}, Duration: $durationText ($durationDays days)');
      
      // Create entries for the duration period
      for (int i = 0; i < durationDays; i++) {
        DateTime scheduleDate = startDate.add(Duration(days: i));
        String formattedDate = DateFormat('yyyy-MM-dd').format(scheduleDate);
        
        // Ensure times are properly formatted
        List<String> times = [];
        if (medicine['mappedTime'] is List) {
          times = List<String>.from((medicine['mappedTime'] as List).where((item) => item != null).cast<String>());
        } else if (medicine['mappedTime'] is String) {
          times = [medicine['mappedTime']];
        } else {
          times = _getDefaultTimesForFrequency(
            medicine['mappedTiming'] ?? medicine['timing'] ?? 'Morning',
            medicine['mappedFrequency'] ?? medicine['frequency'] ?? 'Once Daily'
          );
        }
        
        allMedicineData.add({
          'name': medicine['name'] ?? '',
          'dosage': '${medicine['dosage'] ?? ''}${medicine['unit'] ?? ''}',
          'type': medicine['type'] ?? 'Tablet',
          'frequency': medicine['mappedFrequency'] ?? medicine['frequency'] ?? 'Once Daily',
          'timing': medicine['mappedTiming'] ?? medicine['timing'] ?? 'Morning',
          'time': times.join(', '), // Join times as string for display
          'instructions': medicine['instructions'] ?? '',
          'isValidated': medicine['validated'] ?? false,
          'foodInstructions': TimingUtils.mapFoodInstructionsFromPrescription(medicine['instructions'] ?? ''),
          'scheduleDate': formattedDate, // This is the key field for filtering
          'duration': durationText, // Store the original duration text
          'isFromPrescription': true,
          'isActive': true, // Ensure it's active
          'prescriptionData': prescriptionData,
          'userId': authService.userDetails!.id,
        });
        
        print('📝 Prepared medicine: ${medicine['name']} for $formattedDate');
      }
    }

    // Show optimized loading dialog with progress
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _buildOptimizedLoadingDialog(allMedicineData.length),
    );

    // Use the document-based save method for maximum efficiency
    await medicineService.saveMedicinesDocumentBased(
      authService.userDetails!.id,
      allMedicineData,
      prescriptionData,
      onProgress: (current, total) {
        // Update progress in the dialog
        if (mounted) {
          _updateLoadingProgress(current, total);
        }
      },
    );

    // Close loading dialog
    if (mounted) {
      Navigator.of(context).pop();
    }

    // Calculate total duration for the success message
    int totalDays = 0;
    for (var medicine in medicines) {
      String durationText = medicine['duration'] ?? '';
      int? durationDays = DurationHelper.parseDurationToDays(durationText);
      if (durationDays != null && durationDays > 0) {
        totalDays = totalDays > durationDays ? totalDays : durationDays;
      }
    }
    
    // Default to 1 day if no valid duration found
    if (totalDays == 0) totalDays = 1;
    
    String durationMessage = totalDays == 1 ? '1 day' : 
                           totalDays == 7 ? '1 week' : 
                           totalDays < 7 ? '$totalDays days' : 
                           totalDays < 30 ? '${(totalDays / 7).round()} weeks' : 
                           '${(totalDays / 30).round()} months';
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text('${medicines.length} medicines added starting from today for $durationMessage!'),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );
    
    // Navigate to home screen and show today's medicines
    setState(() {
      _selectedIndex = 0;
      // Optionally, reset selected date to today to show the newly saved medicines
      _selectedDate = DateTime.now();
    });
    
    // Wait for navigation, then refresh
    await Future.delayed(Duration(milliseconds: 500));
    if (mounted) {
      _reloadHomeContent();
    }
    
  } catch (e) {
    // Close loading dialog if open
    if (mounted && Navigator.canPop(context)) {
      Navigator.of(context).pop();
    }
    
    print('❌ Error saving prescription medicines: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error saving medicines: $e'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }
}


  Widget _buildNavItem(IconData icon, IconData activeIcon, String label, int index) {
    bool isSelected = _selectedIndex == index;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        _animationController.reset();
        _animationController.forward();
        
        // Refresh name when switching to home tab
        if (index == 0) {
          _loadUserNameFromPrefs();
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF6B46C1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? activeIcon : icon,
              color: isSelected ? Colors.white : Colors.grey.shade500,
              size: 24,
            ),
            if (isSelected) ...[
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      )
    );
  }

  Widget _buildDrugFoodInteractionItem() {
    bool isSelected = _selectedIndex == 1;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = 1;
        });
        _animationController.reset();
        _animationController.forward();
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 8,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Color(0xFF6B46C1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.medication : Icons.medication_outlined,
              color: isSelected ? Colors.white : Colors.grey.shade500,
              size: 24,
            ),
            if (isSelected) ...[
              SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drug-Food',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                  SizedBox(height: 1),
                  Text(
                    'Interaction',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      )
    );
  }

  Widget _buildScanButton() {
    bool isSelected = _selectedIndex == 2;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = 2;
        });
        _animationController.reset();
        _animationController.forward();
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 16 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: Color(0xFF6B46C1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              color: Colors.white,
              size: 20,
            ),
            if (isSelected) ...[
              SizedBox(width: 8),
              Text(
                'Scan',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        )
      )
    );
  }

  void _handleBackgroundNotification(Map<String, dynamic> data) {
    final action = data['action'] as String?;
    final notificationData = data['data'] as Map<String, dynamic>?;
    
    if (notificationData == null) return;
    
    switch (action) {
      case 'take':
        _handleTakeMedicine(notificationData);
        break;
      case 'snooze':
        _handleSnooze(notificationData);
        break;
      default:
        setState(() {
          _selectedIndex = 0;
          _reloadHomeContent();
        });
        break;
    }
  }

  void _handleTakeMedicine(Map<String, dynamic>? data) {
    if (data == null) return;
    _navigateToCardDetail({
      'name': data['medicineName'],
      'dosage': data['dosage'],
      'timing': data['timing'],
      'instructions': data['instructions'],
      'time': data['scheduled_time'],
      'isFromPrescription': false,
    });
  }

  Future<void> _handleSnooze(Map<String, dynamic>? data) async {
    if (data == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      final originalId = data['id'] ?? data['medicineId'] ?? '';
      
      // Get custom snooze duration from preferences
      final snoozeDuration = prefs.getInt(NotificationService.snoozeDurationKey) ?? 5;
      
      // Extract medicine name from data
      final medicineName = data['medicineName'] ?? 'Medicine';
      
      // Calculate snooze time using the custom duration
      final snoozeTime = DateTime.now().add(Duration(minutes: snoozeDuration));
      final formattedTime = DateFormat('h:mm a').format(snoozeTime);
      
      // Create unique snooze ID based on original ID and timestamp
      final snoozeTimestamp = snoozeTime.millisecondsSinceEpoch;
      final uniqueSnoozeId = '${originalId}_${snoozeTimestamp}';
      
      final snoozeData = {
        ...data,
        'snoozeId': uniqueSnoozeId,
        'originalId': originalId,
        'originalTime': data['time'],
        'snoozeTime': snoozeTime.toIso8601String(),
        'scheduledTime': snoozeTime.toIso8601String(),
        'time': DateFormat('HH:mm').format(snoozeTime),
        'snoozedAt': DateTime.now().toIso8601String(),
        'isSnooze': true,
        'snoozeCount': (data['snoozeCount'] ?? 0) + 1,
        'snoozeDuration': snoozeDuration,
      };
      
      final snoozeKey = 'snoozed_alarm_$uniqueSnoozeId';
      await prefs.setString(snoozeKey, jsonEncode(snoozeData));
      
      final oldSnoozeKeys = allKeys.where((key) => 
        key.startsWith('snoozed_alarm_${originalId}_') && 
        key != snoozeKey
      ).toList();
      
      for (var oldKey in oldSnoozeKeys) {
        await prefs.remove(oldKey);
      }
      
      await _notificationService.scheduleSingleMedicationReminder(snoozeData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.alarm, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reminder snoozed for $snoozeDuration minutes',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$medicineName will remind you at $formattedTime',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            duration: Duration(seconds: 4),
            backgroundColor: Colors.blue.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: EdgeInsets.all(10),
          ),
        );
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error snoozing alarm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadAndRescheduleSnoozedAlarms() async {
    if (!mounted) return;
    
    try {
      print('🔄 Loading and rescheduling snoozed alarms...');
      
      // Get snoozed alarms from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      
      // Check both Flutter's keys and the ones potentially stored by native code
      Set<String> allKeys = prefs.getKeys().toSet();
      
      // Add any keys from the native SharedPreferences if available
      try {
        // Try to get any snoozed alarms from the native side
        final nativeAlarms = await _notificationService.getSnoozedAlarms();
        
        if (nativeAlarms.isNotEmpty) {
          for (var alarmItem in nativeAlarms) {
            final key = alarmItem['key'] as String;
            final alarmData = alarmItem['data'] as Map<String, dynamic>;
            
            // Store in Flutter's SharedPreferences to ensure consistency
            await prefs.setString(key, jsonEncode(alarmData));
            allKeys.add(key);
          }
          
          print('🔄 Retrieved ${nativeAlarms.length} snoozed alarms from native storage');
        }
      } catch (e) {
        print('⚠️ Could not retrieve native snoozed alarms: $e');
      }
      
      // Filter for snooze keys
      final snoozeKeys = allKeys.where((key) => key.startsWith('snoozed_alarm_')).toList();
      
      print('🔍 All SharedPreferences keys: ${allKeys.length}');
      print('🔍 Found ${snoozeKeys.length} snoozed alarm keys: $snoozeKeys');
      
      if (snoozeKeys.isEmpty) {
        print('ℹ️ No snoozed alarms found in SharedPreferences');
        return;
      }
      
      // Sort keys by timestamp to process oldest first
      snoozeKeys.sort((a, b) {
        try {
          // Extract timestamp from keys
          final aTimestamp = int.parse(a.split('_').last);
          final bTimestamp = int.parse(b.split('_').last);
          return aTimestamp.compareTo(bTimestamp);
        } catch (e) {
          return 0;
        }
      });
      
      int rescheduledCount = 0;
      int expiredCount = 0;
      
      for (var key in snoozeKeys) {
        if (!mounted) return;
        
        final snoozeDataString = prefs.getString(key);
        if (snoozeDataString != null && snoozeDataString.isNotEmpty) {
          try {
            final snoozeData = jsonDecode(snoozeDataString);
            
            // Try different time fields that might exist in the data
            DateTime? snoozeTime;
            if (snoozeData.containsKey('snoozeTime')) {
              if (snoozeData['snoozeTime'] is int) {
                // Native code stores as millisecond timestamp
                snoozeTime = DateTime.fromMillisecondsSinceEpoch(snoozeData['snoozeTime']);
              } else {
                // Flutter stores as ISO8601 string
                snoozeTime = DateTime.tryParse(snoozeData['snoozeTime'].toString());
              }
            } else if (snoozeData.containsKey('scheduledTime')) {
              snoozeTime = DateTime.tryParse(snoozeData['scheduledTime'].toString());
            } else if (snoozeData.containsKey('trigger_time')) {
              snoozeTime = DateTime.tryParse(snoozeData['trigger_time'].toString());
            }
            
            // Fallback if time not found
            snoozeTime ??= DateTime.now().add(Duration(minutes: 5));
            
            final now = DateTime.now();
            final medicineName = snoozeData['medicineName'] ?? 'Medicine';
            
            print('⏰ Processing snoozed alarm: $medicineName scheduled for $snoozeTime');
            
            // Make sure we have all required fields
            Map<String, dynamic> enhancedSnoozeData = Map<String, dynamic>.from(snoozeData);
            enhancedSnoozeData['isSnooze'] = true;
            enhancedSnoozeData['medicineName'] ??= 'Medicine';
            
            // Make sure snoozeDuration is included
            if (!enhancedSnoozeData.containsKey('snoozeDuration')) {
              // Try to get from preferences first
              final snoozeDuration = prefs.getInt(NotificationService.snoozeDurationKey) ?? 5;
              enhancedSnoozeData['snoozeDuration'] = snoozeDuration;
              print('📝 Added missing snoozeDuration: $snoozeDuration');
            }
            
            if (snoozeTime.isAfter(now)) {
              // Reschedule the snoozed alarm with correct timing
              print('✅ Rescheduling snoozed alarm for: $snoozeTime');
              if (mounted) {
                // CRITICAL: Ensure snoozeTime is properly set and stored as ISO8601 string
                enhancedSnoozeData['snoozeTime'] = snoozeTime.toIso8601String();
                
                // Also ensure we have the original alarm ID for proper tracking
                if (!enhancedSnoozeData.containsKey('originalAlarmId') && enhancedSnoozeData.containsKey('alarmId')) {
                  enhancedSnoozeData['originalAlarmId'] = enhancedSnoozeData['alarmId'];
                }
                
                // Log the data being passed to ensure it's correct
                print('📋 Enhanced snooze data: ${jsonEncode(enhancedSnoozeData)}');
                
                await _notificationService.scheduleSingleMedicationReminder(enhancedSnoozeData);
                rescheduledCount++;
              }
            } else {
              // Remove expired snoozed alarm
              print('🗑️ Removing expired snoozed alarm: $key');
              await prefs.remove(key);
              expiredCount++;
            }
          } catch (e) {
            print('❌ Error processing snoozed alarm $key: $e');
            print('❌ Raw data: $snoozeDataString');
            // Remove corrupted data
            await prefs.remove(key);
          }
        } else {
          print('⚠️ Empty snooze data for key: $key');
          await prefs.remove(key);
        }
      }
      
      print('✅ Rescheduled $rescheduledCount snoozed alarms, removed $expiredCount expired alarms');
    } catch (e) {
      print('❌ Error loading snoozed alarms: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      
      return Scaffold(
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: _getCurrentScreen(),
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            child: Container(
              height: 75,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(Icons.home_outlined, Icons.home, 'Home', 0),
                  _buildDrugFoodInteractionItem(),
                  _buildScanButton(),
                  _buildNavItem(Icons.people_outline, Icons.people, 'Caretaker', 3),
                  _buildNavItem(Icons.settings_outlined, Icons.settings, 'Settings', 4),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e, stack) {
      print('Build error: $e\n$stack');
      return Scaffold(
        body: Center(
          child: Text(
            'An error occurred.\n$e',
            style: TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _navigationSubscription.cancel();
    _snoozeSubscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // App came to foreground, check permissions
      _checkPermissionsOnResume();
    }
  }

  Future<void> _checkPermissionsOnResume() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (!authService.isAuthenticated) return;

      if (!mounted) return;

      final notificationPermission = await Permission.notification.isGranted;
      final exactAlarmPermission = await Permission.scheduleExactAlarm.isGranted;
      final overlay = await _notificationService.isOverlayPermissionGranted();
      
      final permissions = {
        'notifications': notificationPermission,
        'exact_alarms': exactAlarmPermission,
        'overlay': overlay,
        'all_granted': notificationPermission && exactAlarmPermission && overlay,
      };
      
      // Show permission dialog if any permission is not granted
      if (!permissions['all_granted']!) {
        _showComprehensivePermissionDialog(permissions);
      }
    } catch (e) {
      print('Error checking permissions on resume: $e');
    }
  }

  // Loading dialog methods
  Widget _buildOptimizedLoadingDialog(int totalItems) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Container(
        width: 300,
        height: 120,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6B46C1)),
            ),
            SizedBox(height: 16),
            Text(
              'Saving medicines...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Processing $totalItems medicines',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateLoadingProgress(int current, int total) {
    // This method can be used to update progress if needed
    // For now, we'll just print the progress
    print('Progress: $current / $total');
  }
}

class HomeContent extends StatefulWidget {
  final Function(Map<String, dynamic>) onNavigateToDetail;
  final DateTime selectedDate;
  final Function(DateTime) onDateSelected;
  final String savedName;
  final Function(String) onNameUpdated;

  HomeContent({
    Key? key, 
    required this.onNavigateToDetail,
    required this.selectedDate,
    required this.onDateSelected,
    required this.savedName,
    required this.onNameUpdated,
  }) : super(key: key);

  @override
  _HomeContentState createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with TickerProviderStateMixin {
  // Use the passed selectedDate instead of having our own
  DateTime get _selectedDate => widget.selectedDate;
  
  final ScrollController _scrollController = ScrollController();
  late AnimationController _cardAnimationController;
  List<Map<String, dynamic>> medicineData = [];
  bool _isLoading = false;
  bool _isLoadingCards = false;
  final NotificationService _notificationService = NotificationService();
  // Store a reference to AuthService
  AuthService? _authService;
  
  // Track last medicine data hash to prevent redundant scheduling
  String _lastMedicineDataHash = '';
  
  // Medicine type icon mapping
  IconData _getMedicineTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'tablet':
        return Symbols.pill_rounded;
      case 'capsule':
        return Symbols.medication_liquid_rounded;
      case 'syrup':
        return Symbols.water_bottle_rounded;
      case 'injection':
        return Symbols.syringe_rounded;
      case 'drops':
        return Symbols.dropper_eye_rounded;
      case 'cream':
        return  Symbols.healing_rounded;
      case 'inhaler':
        return Symbols.air_rounded;
      case 'powder':
        return Symbols.grain_rounded;
      case 'gel':
        return Icons.water_drop_rounded;
      case 'spray':
        return Icons.sanitizer_rounded;
      case 'patch':
        return Symbols.healing_rounded;
      case 'suppository':
        return Symbols.medication_rounded;
      case 'lotion':
        return Symbols.sanitizer_rounded;
      case 'ointment':
        return Symbols.medication_liquid_rounded;
      case 'solution':
        return Symbols.water_full_rounded;
      case 'device':
        return Symbols.monitoring_rounded;
      case 'implant':
        return Symbols.biotech_rounded;
      default:
        return Symbols.pill_rounded;
    }
  }

  String _formatMedicineType(String type) {
    if (type.isEmpty) return 'Tablet';
    return type[0].toUpperCase() + type.substring(1).toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _cardAnimationController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Store the reference to AuthService
      _authService = Provider.of<AuthService>(context, listen: false);
      if (_authService?.userDetails != null) {
        _loadMedicineData();
      } else {
        _authService?.addListener(_onAuthChanged);
      }
      _scrollToToday();
      _cardAnimationController.forward();
    });
  }

  void _onAuthChanged() {
    if (mounted) {
      _loadMedicineData();
    }
  }
  
  // Add a field to store the calendar card state reference
  _CalendarCardState? _calendarCardState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Store a reference to the calendar card state
    _calendarCardState = context.findAncestorStateOfType<_CalendarCardState>();
  }
  
  @override
  void didUpdateWidget(HomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the selected date changed, reload the medicine data
    if (oldWidget.selectedDate != widget.selectedDate) {
      // Reset animation and reload data
      _cardAnimationController.reset();
      _loadMedicineData().then((_) {
        if (mounted) {
          _cardAnimationController.forward();
        }
      });
    }
  }

  Future<void> _loadAndRescheduleSnoozedAlarms() async {
    if (!mounted) return;
    
    try {
      print('🔄 Loading and rescheduling snoozed alarms...');
      
      // Get snoozed alarms from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      
      // Check both Flutter's keys and the ones potentially stored by native code
      Set<String> allKeys = prefs.getKeys().toSet();
      
      // Add any keys from the native SharedPreferences if available
      try {
        // Try to get any snoozed alarms from the native side
        final nativeAlarms = await _notificationService.getSnoozedAlarms();
        
        if (nativeAlarms.isNotEmpty) {
          for (var alarmItem in nativeAlarms) {
            final key = alarmItem['key'] as String;
            final alarmData = alarmItem['data'] as Map<String, dynamic>;
            
            // Store in Flutter's SharedPreferences to ensure consistency
            await prefs.setString(key, jsonEncode(alarmData));
            allKeys.add(key);
          }
          
          print('🔄 Retrieved ${nativeAlarms.length} snoozed alarms from native storage');
        }
      } catch (e) {
        print('⚠️ Could not retrieve native snoozed alarms: $e');
      }
      
      // Filter for snooze keys
      final snoozeKeys = allKeys.where((key) => key.startsWith('snoozed_alarm_')).toList();
      
      print('🔍 All SharedPreferences keys: ${allKeys.length}');
      print('🔍 Found ${snoozeKeys.length} snoozed alarm keys: $snoozeKeys');
      
      if (snoozeKeys.isEmpty) {
        print('ℹ️ No snoozed alarms found in SharedPreferences');
        return;
      }
      
      // Sort keys by timestamp to process oldest first
      snoozeKeys.sort((a, b) {
        try {
          // Extract timestamp from keys
          final aTimestamp = int.parse(a.split('_').last);
          final bTimestamp = int.parse(b.split('_').last);
          return aTimestamp.compareTo(bTimestamp);
        } catch (e) {
          return 0;
        }
      });
      
      int rescheduledCount = 0;
      int expiredCount = 0;
      
      for (var key in snoozeKeys) {
        if (!mounted) return;
        
        final snoozeDataString = prefs.getString(key);
        if (snoozeDataString != null && snoozeDataString.isNotEmpty) {
          try {
            final snoozeData = jsonDecode(snoozeDataString);
            
            // Try different time fields that might exist in the data
            DateTime? snoozeTime;
            if (snoozeData.containsKey('snoozeTime')) {
              if (snoozeData['snoozeTime'] is int) {
                // Native code stores as millisecond timestamp
                snoozeTime = DateTime.fromMillisecondsSinceEpoch(snoozeData['snoozeTime']);
              } else {
                // Flutter stores as ISO8601 string
                snoozeTime = DateTime.tryParse(snoozeData['snoozeTime'].toString());
              }
            } else if (snoozeData.containsKey('scheduledTime')) {
              snoozeTime = DateTime.tryParse(snoozeData['scheduledTime'].toString());
            } else if (snoozeData.containsKey('trigger_time')) {
              snoozeTime = DateTime.tryParse(snoozeData['trigger_time'].toString());
            }
            
            // Fallback if time not found
            snoozeTime ??= DateTime.now().add(Duration(minutes: 5));
            
            final now = DateTime.now();
            final medicineName = snoozeData['medicineName'] ?? 'Medicine';
            
            print('⏰ Processing snoozed alarm: $medicineName scheduled for $snoozeTime');
            
            // Make sure we have all required fields
            Map<String, dynamic> enhancedSnoozeData = Map<String, dynamic>.from(snoozeData);
            enhancedSnoozeData['isSnooze'] = true;
            enhancedSnoozeData['medicineName'] ??= 'Medicine';
            
            // Make sure snoozeDuration is included
            if (!enhancedSnoozeData.containsKey('snoozeDuration')) {
              // Try to get from preferences first
              final snoozeDuration = prefs.getInt(NotificationService.snoozeDurationKey) ?? 5;
              enhancedSnoozeData['snoozeDuration'] = snoozeDuration;
              print('📝 Added missing snoozeDuration: $snoozeDuration');
            }
            
            if (snoozeTime.isAfter(now)) {
              // Reschedule the snoozed alarm with correct timing
              print('✅ Rescheduling snoozed alarm for: $snoozeTime');
              if (mounted) {
                // CRITICAL: Ensure snoozeTime is properly set and stored as ISO8601 string
                enhancedSnoozeData['snoozeTime'] = snoozeTime.toIso8601String();
                
                // Also ensure we have the original alarm ID for proper tracking
                if (!enhancedSnoozeData.containsKey('originalAlarmId') && enhancedSnoozeData.containsKey('alarmId')) {
                  enhancedSnoozeData['originalAlarmId'] = enhancedSnoozeData['alarmId'];
                }
                
                // Log the data being passed to ensure it's correct
                print('📋 Enhanced snooze data: ${jsonEncode(enhancedSnoozeData)}');
                
                await _notificationService.scheduleSingleMedicationReminder(enhancedSnoozeData);
                rescheduledCount++;
              }
            } else {
              // Remove expired snoozed alarm
              print('🗑️ Removing expired snoozed alarm: $key');
              await prefs.remove(key);
              expiredCount++;
            }
          } catch (e) {
            print('❌ Error processing snoozed alarm $key: $e');
            print('❌ Raw data: $snoozeDataString');
            // Remove corrupted data
            await prefs.remove(key);
          }
        } else {
          print('⚠️ Empty snooze data for key: $key');
          await prefs.remove(key);
        }
      }
      
      print('✅ Rescheduled $rescheduledCount snoozed alarms, removed $expiredCount expired alarms');
    } catch (e) {
      print('❌ Error loading snoozed alarms: $e');
    }
  }
  
  Future<void> _loadMedicineData() async {
    if (!mounted) return;

    setState(() {
      _isLoadingCards = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.userDetails != null) {
        // We don't need to manually fetch medicine data anymore since StreamBuilder handles it
        // Just reset animation and handle snoozed alarms
        
        // CRITICAL: Load snoozed alarms
        if (mounted) {
          await _loadAndRescheduleSnoozedAlarms();
        }
        
        // The StreamBuilder will handle updating the medicineData list and scheduling notifications
      }
    } catch (e) {
      print('❌ Error loading medicines: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading medicines: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingCards = false;
        });
      }
    }
  }

  void _scrollToToday() {
    // Check if the scroll controller is attached before trying to animate
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onDateSelected(DateTime date) {
    // Call the parent's onDateSelected
    widget.onDateSelected(date);
    
    // Reset the animation controller before reloading data
    _cardAnimationController.reset();
    
    // Reload medicine data for the selected date
    _loadMedicineData().then((_) {
      // Forward the animation after data is loaded
      if (mounted) {
        _cardAnimationController.forward();
        
        // Use the stored reference instead of looking it up dynamically
        if (_calendarCardState != null && _calendarCardState!.mounted) {
          _calendarCardState!._loadMedicineDates();
        }
      }
    });
  }

  Future<void> _deleteMedicine(String medicineId, String medicineName, Map<String, dynamic> medicineData) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.userDetails != null) {
        // Check if this is a duration-based medicine from prescription
        bool isDurationBased = medicineData['isDurationBased'] ?? false;
        bool isFromPrescription = medicineData['isFromPrescription'] ?? false;
        String? prescriptionId = medicineData['prescriptionId'];
        String? duration = medicineData['duration'];
        
        // For duration-based medicines, default to deleting all related entries
        // For regular medicines, just delete the single entry
        bool deleteAllRelated = isDurationBased || (isFromPrescription && prescriptionId != null);
        
        await _performDelete(medicineId, medicineName, deleteAllRelated);
      }
    } catch (e) {
      print('Error deleting medicine: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting medicine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }



  Future<void> _performDelete(String medicineId, String medicineName, bool deleteAllRelated) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.userDetails != null) {
        final medicineService = MedicineService();
        
        // Format the selected date for the deletion
        final String selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        
        // Extract the original medicine ID from the composite ID (format: originalId_selectedDate)
        String originalMedicineId = medicineId;
        if (medicineId.contains('_') && medicineId.endsWith('_$selectedDateStr')) {
          // More robust extraction: find the last occurrence of the date pattern
          final datePattern = '_$selectedDateStr';
          if (medicineId.endsWith(datePattern)) {
            originalMedicineId = medicineId.substring(0, medicineId.length - datePattern.length);
            print('🔍 Extracted original medicine ID: $originalMedicineId from composite ID: $medicineId');
          }
        }
        
        if (deleteAllRelated) {
          // Delete all related entries (duration-based or prescription-based)
          await medicineService.deleteAllRelatedMedicines(
            authService.userDetails!.id, 
            originalMedicineId
          );
        } else {
          // Delete only this specific medicine entry for the selected date
          await medicineService.deleteMedicine(
            authService.userDetails!.id, 
            originalMedicineId,
            selectedDate: selectedDateStr
          );
        }
        
        // Force refresh the StreamBuilder by updating trigger field
        await FirebaseFirestore.instance
            .collection('users')
            .doc(authService.userDetails!.id)
            .update({
              'medicationUpdateTrigger': FieldValue.serverTimestamp(),
            }).then((_) {
              print('✅ Updated trigger field');
            }).catchError((e) {
              print('❌ Error updating trigger: $e');
            });
        
        // Clear local medicine data to ensure UI consistency
        if (mounted) {
          setState(() {
            medicineData = [];
            _lastMedicineDataHash = '';
          });
          
          // Add a small delay to ensure Firestore propagation
          await Future.delayed(Duration(milliseconds: 300));
          
          // Force a rebuild to refresh the UI
          setState(() {});
        }
        
        // Use the stored reference instead of looking it up dynamically
        if (_calendarCardState != null && _calendarCardState!.mounted) {
          await _calendarCardState!._loadMedicineDates();
        }
        
        if (mounted) {
          String message = deleteAllRelated 
              ? '$medicineName and all related entries deleted successfully'
              : '$medicineName deleted for ${DateFormat('MMM d, yyyy').format(_selectedDate)}';
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      print('Error deleting medicine: $e');
      if (mounted) {
        // Check if the error is about medicine not found (which is not really an error)
        if (e.toString().contains('not found') || e.toString().contains('not-found')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.info, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('$medicineName was already removed')),
                ],
              ),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting medicine: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // Removed _getMedicineColor method as we're using fixed gradient colors

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 16,
                    color: Colors.white,
                  ),
                  SizedBox(height: 8),
                  Container(
                    width: 150,
                    height: 14,
                    color: Colors.white,
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Container(width: 60, height: 12, color: Colors.white),
                      SizedBox(width: 8),
                      Container(width: 80, height: 12, color: Colors.white),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF6B46C1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset(
            'assets/images/logo.png',
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.medical_services, color: Colors.white),
          ),
        ),
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Medic',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
              ),
              TextSpan(
                text: 'Food',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 20),
              ),
            ],
          ),
        ),
        actions: [
          Consumer<AuthService>(
            builder: (context, authService, child) {
              return GestureDetector(
                onTap: () {
                  _showProfileMenu(context, authService);
                },
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundColor: Colors.blue.shade400,
                    backgroundImage: authService.userDetails?.photoUrl.isNotEmpty == true
                        ? NetworkImage(authService.userDetails!.photoUrl)
                        : null,
                    child: authService.userDetails?.photoUrl.isEmpty != false
                        ? Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: 16),
        ],
      ),
      body: Consumer<AuthService>(
        builder: (context, authService, child) {
          if (authService.isLoading || _isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: _loadMedicineData,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Consumer<AuthService>(
                            builder: (context, authService, child) {
                              return RichText(
                              text: TextSpan(
                                children: [
                                TextSpan(
                                  text: 'Hello\n',
                                  style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.normal,
                                  color: const Color.fromARGB(221, 43, 40, 40), 
                                  letterSpacing:  1.2,
                                  ),
                                ),
                                TextSpan(
                                  text: widget.savedName.isNotEmpty ? '${widget.savedName}!' : '',
                                  style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  letterSpacing: 1.5,
                                  ),
                                ),
                                ],
                              ),
                              );
                            },
                          ),
                          SizedBox(height: 8),
                          Text(
                            DateFormat('EEEE, MMMM d').format(DateTime.now()),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${medicineData.length}',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            Text(
                              'Today\'s\nMeds',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  CalendarCard(
                    onDateSelected: (DateTime date) {
                      _onDateSelected(date);
                    },
                    selectedDate: _selectedDate,
                  ),
                  
                  Transform.translate(
                    offset: Offset(0, -20), // Apply negative vertical offset
                    child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('yyyy-MM-dd').format(_selectedDate) == DateFormat('yyyy-MM-dd').format(DateTime.now())
                            ? 'Today\'s Medication'
                            : 'Medication for ${DateFormat('MMM d').format(_selectedDate)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => PrescriptionScannerScreen(
                              onPrescriptionScanned: widget.onNavigateToDetail,
                            )),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Color.fromARGB(255, 240, 43, 43),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.document_scanner_outlined, color: Colors.white, size: 16),
                              SizedBox(width: 6),
                              Text(
                                'Scan Prescription',
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
                    ],
                  ),
                  ),
                  SizedBox(height: 16),

                  AnimatedBuilder(
                    animation: _cardAnimationController,
                    builder: (context, child) {
                      return Column(
                        children: [
                          // Add Medicine Card (always first)
                          SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset(1.0, 0.0),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: _cardAnimationController,
                              curve: Interval(0.0, 1.0, curve: Curves.easeOutCubic),
                            )),
                            child: FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _cardAnimationController,
                                curve: Interval(0.0, 1.0, curve: Curves.easeOut),
                              ),
                              child: Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: _buildAddMedicineCard(),
                              ),
                            ),
                          ),
                          
                          // Implement nested StreamBuilder for real-time updates
                          Consumer<AuthService>(
                            builder: (context, authService, child) {
                              if (authService.userDetails == null) {
                                return Center(child: Text('Please sign in to view medications'));
                              }
                              
                              final currentUser = authService.userDetails!;
                              final String selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
                              
                              return StreamBuilder<DocumentSnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(currentUser.id)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  // Check for user document updates (especially medicationUpdateTrigger)
                                  // This will rebuild when caretakers make changes
                                  if (snapshot.hasData) {
                                    final userData = snapshot.data!.data() as Map<String, dynamic>?;
                                    // We don't need to use userData directly, just having this listener
                                    // ensures we rebuild when caretakers update the medicationUpdateTrigger field
                                  }
                                  
                                  return StreamBuilder<DocumentSnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(currentUser.id)
                                        .collection('medicine_schedules')
                                        .doc('current_schedule')
                                        .snapshots(),
                                    builder: (context, medicationSnapshot) {
                                      if (medicationSnapshot.connectionState == ConnectionState.waiting && !medicationSnapshot.hasData) {
                                        return Column(
                                          children: List.generate(3, (index) => _buildShimmerCard()),
                                        );
                                      }
                                      
                                      if (medicationSnapshot.hasError) {
                                        print("Error in medication snapshot: ${medicationSnapshot.error}");
                                        return Center(child: Text('Error loading medications'));
                                      }
                                      
                                      // Handle document-based medicine data
                                      List<Map<String, dynamic>> filteredMedicines = [];
                                      
                                      if (medicationSnapshot.hasData && medicationSnapshot.data!.exists) {
                                        final data = medicationSnapshot.data!.data() as Map<String, dynamic>?;
                                        if (data != null && data.containsKey('medicines')) {
                                          final medicines = data['medicines'] as Map<String, dynamic>?;
                                          if (medicines != null) {
                                          print('🔍 StreamBuilder: Found ${medicines.length} medicines in schedule');
                                          
                                          // Track processed medicines to prevent duplicates
                                          Set<String> processedMedicineIds = {};
                                          
                                          // Process each medicine schedule
                                          for (var entry in medicines.entries) {
                                            final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
                                            final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
                                            final duration = medicineSchedule['duration']?.toString() ?? '';
                                            
                                            // Check if this medicine should appear on the selected date based on duration
                                            bool shouldShowOnDate = false;
                                            String? actualScheduleDate;
                                            
                                            // First check if the date is explicitly in scheduleDates
                                            if (scheduleDates.contains(selectedDateStr)) {
                                              shouldShowOnDate = true;
                                              actualScheduleDate = selectedDateStr;
                                            } else {
                                              // If not explicitly scheduled, check if it's within the duration period
                                              if (duration.isNotEmpty && scheduleDates.isNotEmpty) {
                                                // Get the start date from scheduleDates
                                                final startDateStr = scheduleDates.first;
                                                try {
                                                  final startDate = DateTime.parse(startDateStr);
                                                  final selectedDate = DateTime.parse(selectedDateStr);
                                                  
                                                  // Parse duration to get number of days
                                                  final durationDays = DurationHelper.parseDurationToDays(duration);
                                                  if (durationDays != null && durationDays > 0) {
                                                    final endDate = startDate.add(Duration(days: durationDays - 1));
                                                    
                                                    // Check if selected date is within the duration period
                                                    if (selectedDate.isAfter(startDate.subtract(Duration(days: 1))) && 
                                                        selectedDate.isBefore(endDate.add(Duration(days: 1)))) {
                                                      shouldShowOnDate = true;
                                                      actualScheduleDate = startDateStr;
                                                      print('🔍 Medicine ${medicineSchedule['name']} should show on $selectedDateStr (duration: $duration, start: $startDateStr, end: ${endDate.toIso8601String().split('T')[0]})');
                                                    }
                                                  }
                                                } catch (e) {
                                                  print('⚠️ Error parsing dates for duration calculation: $e');
                                                }
                                              }
                                            }
                                            
                                            if (shouldShowOnDate) {
                                              // Construct medicine ID in the format: ${entry.key}_$date
                                              // This matches the format used in the medicine service
                                              final medicineId = '${entry.key}_$actualScheduleDate';
                                              
                                              // Skip if we've already processed this medicine
                                              if (processedMedicineIds.contains(medicineId)) {
                                                print('🔍 Skipping duplicate medicine: ${medicineSchedule['name']} (ID: $medicineId)');
                                                continue;
                                              }
                                              
                                              // Find the specific schedule data for this date
                                              final scheduleData = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData'] ?? []);
                                              final dateSchedule = scheduleData.firstWhere(
                                                (schedule) => schedule['date'] == actualScheduleDate,
                                                orElse: () => {
                                                  'date': actualScheduleDate,
                                                  'time': medicineSchedule['time'] ?? '08:00 AM',
                                                  'isCompleted': false,
                                                  'completedAt': null,
                                                },
                                              );
                                              
                                              // Create medicine entry with all necessary data
                                              final medicineEntry = {
                                                ...medicineSchedule,
                                                'scheduleDate': actualScheduleDate,
                                                'time': dateSchedule['time'],
                                                'isCompleted': dateSchedule['isCompleted'] ?? false,
                                                'completedAt': dateSchedule['completedAt'],
                                                'id': medicineId, // Ensure ID is included
                                                'frontImagePath': medicineSchedule['frontImagePath'], // Include image paths
                                                'backImagePath': medicineSchedule['backImagePath'], // Include image paths
                                                'voiceFilePath': medicineSchedule['voiceFilePath'], // Include voice recordings
                                              };
                                              
                                              filteredMedicines.add(medicineEntry);
                                              processedMedicineIds.add(medicineId); // Mark as processed
                                              print('🔍 Added medicine: ${medicineSchedule['name']} (ID: $medicineId)');
                                              print('🔍 Asset paths - Front: ${medicineSchedule['frontImagePath']}, Back: ${medicineSchedule['backImagePath']}, Voice: ${medicineSchedule['voiceFilePath']}');
                                            }
                                          }
                                        }
                                      }
                                      }
                                      
                                      // Sort by time
                                      filteredMedicines.sort((a, b) {
                                        final aTime = a['time'] ?? '';
                                        final bTime = b['time'] ?? '';
                                        return aTime.toString().compareTo(bTime.toString());
                                      });
                                      
                                      print('🔍 StreamBuilder: Filtered medicines count: ${filteredMedicines.length}');
                                      
                                      // Log each medicine that was added
                                      for (var medicine in filteredMedicines) {
                                        print('🔍 Medicine on calendar: ${medicine['name']} - Duration: "${medicine['duration']}" - Date: ${medicine['scheduleDate']}');
                                      }
                                      
                                      // Update local state for other parts of the UI
                                      if (mounted) {
                                        // Only update the medicine data and schedule if it has actually changed
                                        final newMedicineData = filteredMedicines;
                                        
                                        // Check if medicine data has actually changed before rescheduling
                                        final String newDataHash = _generateMedicineDataHash(newMedicineData);
                                        if (newDataHash != _lastMedicineDataHash) {
                                          medicineData = newMedicineData;
                                          _lastMedicineDataHash = newDataHash;
                                          
                                          // Schedule notifications only when medicine data has changed
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (mounted) {
                                              print("📅 Medicine data changed, rescheduling reminders");
                                              _notificationService.scheduleMedicationReminders(medicineData);
                                            }
                                          });
                                        }
                                      }
                                      
                                      if (filteredMedicines.isEmpty) {
                                        return SizedBox.shrink();
                                      }

                                      return Column(
                                        children: filteredMedicines.asMap().entries.map((entry) {
                              int index = entry.key;
                                          final medicine = entry.value;
                              
                              // Calculate animation timing with proper bounds checking
                                          final begin = ((index + 1) * 0.1).clamp(0.0, 0.9);
                                          final end = (begin + 0.1).clamp(0.0, 1.0);
                              
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(CurvedAnimation(
                                  parent: _cardAnimationController,
                                  curve: Interval(
                                    begin,
                                    end,
                                    curve: Curves.easeOutCubic,
                                  ),
                                )),
                                child: FadeTransition(
                                  opacity: CurvedAnimation(
                                    parent: _cardAnimationController,
                                    curve: Interval(
                                      begin,
                                      end,
                                      curve: Curves.easeOut,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 12),
                                    child: _buildMedicineCard(
                                      medicine['name'] ?? '',
                                      medicine['dosage'] ?? '',
                                      medicine['time'] ?? '',
                                      medicine['timing'] ?? '',
                                      medicine,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAddMedicineCard() {
    return GestureDetector(
      onTap: () {
        // Format the selected date to match the stored format
        String selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
        
        widget.onNavigateToDetail({
          'name': '',
          'dosage': '',
          'time': '08:00 AM',
          'timing': 'Morning', // Changed from 'Anytime' to 'Morning' for consistency
          'type': 'Tablet',
          'frequency': 'Once Daily',
          'instructions': '',
          'foodInstructions': 'Anytime',
          'isFromPrescription': false,
          'scheduleDate': selectedDateStr,
          'isActive': true,
          'lastUpdated': DateTime.now().toIso8601String(),
          'duration': '', // Add duration field
          'isValidated': false, // Add validation field
        });
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Color(0xFF6B46C1).withOpacity(0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(0xFF6B46C1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.add,
                color: Color(0xFF6B46C1),
                size: 24,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set Your Medic Reminder Now',
                    style: TextStyle(
                      color: Color(0xFF6B46C1),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap to add your medicine schedule ',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Color(0xFF6B46C1),
              size: 16,
            ),
          ],
        ),
      )
    );
  }



  Widget _buildMedicineCard(
    String name,
    String dosage,
    String time,
    String timing,
    Map<String, dynamic> medicineData,
  ) {
    // Calculate remaining duration with safe type handling
    final duration = medicineData['duration'] as String?;
    final createdAt = medicineData['createdAt']; // Don't cast to String
    String? durationDisplay;
    
    if (duration != null && duration.isNotEmpty && createdAt != null) {
      final remainingDays = DurationHelper.getRemainingDays(duration, createdAt);
      if (remainingDays != null) {
        if (remainingDays == 0) {
          durationDisplay = "Last day";
        } else if (remainingDays <= 3) {
          durationDisplay = "$remainingDays days left";
        } else if (remainingDays <= 7) {
          durationDisplay = "$remainingDays days left";
        } else {
          durationDisplay = DurationHelper.formatDurationDisplay(duration);
        }
      } else {
        // Indefinite duration
        durationDisplay = duration;
      }
    }
    return GestureDetector(
      onTap: () {
        widget.onNavigateToDetail({
          ...medicineData,
          'name': name,
          'dosage': dosage,
          'time': time,
          'timing': timing,
          'type': medicineData['type'] ?? 'Tablet',
          'foodInstructions': medicineData['foodInstructions'],
          'frequency': medicineData['frequency'] ?? 'Once Daily',
          'instructions': medicineData['instructions'] ?? '',
          'isFromPrescription': medicineData['isFromPrescription'] ?? false,
          'prescriptionData': medicineData['prescriptionData'],
          'id': medicineData['id'],
          'isValidated': medicineData['isValidated'] ?? false,
          'isActive': medicineData['isActive'] ?? true,
          'lastUpdated': medicineData['lastUpdated'] ?? DateTime.now().toIso8601String(),
          'duration': medicineData['duration'] ?? '', // Pass duration to detail screen
        });
      },
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color.fromARGB(255, 77, 25, 137),
              Color(0xFF6A5ACD),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF7B68EE).withOpacity(0.3),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getMedicineTypeIcon(medicineData['type'] ?? ''),
                color: Colors.white,
                size: 20,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "${dosage} - ${medicineData['frequency'] ?? 'Once Daily'}",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),

                  // Duration display
                  if (durationDisplay != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: Colors.white70,
                            size: 12,
                          ),
                          SizedBox(width: 4),
                          Text(
                            durationDisplay,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (time.contains(',')) 
                        ...time.split(',').map((t) => _buildMedicineTag(Icons.access_time, t.trim())).toList()
                      else
                        _buildMedicineTag(Icons.access_time, time),
                      _buildMedicineTag(Icons.restaurant, medicineData['foodInstructions'] ?? 'Anytime'),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.8)),
              onSelected: (value) {
                if (value == 'edit') {
                  widget.onNavigateToDetail(medicineData);
                } else if (value == 'delete_medicine') {
                  // Delete this medicine entry only for the selected date
                  _performDelete(medicineData['id'], name, false);
                } else if (value == 'delete_all_days') {
                  // Delete all related entries
                  _performDelete(medicineData['id'], name, true);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete_medicine',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Delete Medicine', style: TextStyle(color: Colors.orange)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete_all_days',
                  child: Row(
                    children: [
                      Icon(Icons.delete_forever, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete for All Days', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicineTag(IconData icon, String text) {
    String displayText = text;
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text(
            displayText,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Use the stored reference instead of accessing Provider directly
    if (_authService != null) {
      _authService!.removeListener(_onAuthChanged);
    }
    _cardAnimationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showEditProfileDialogFromContent(BuildContext context, AuthService authService) async {
    final TextEditingController nameController = TextEditingController();
                            nameController.text = widget.savedName.isNotEmpty ? widget.savedName : '';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person, color: Colors.blue, size: 24),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Name',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter your name',
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                // Save to SharedPreferences based on authentication status
                final prefs = await SharedPreferences.getInstance();
                if (authService.isAuthenticated && authService.userDetails != null) {
                  // For authenticated users, save per user ID
                  final userId = authService.userDetails!.id;
                  await prefs.setString('name_$userId', newName);
                } else {
                  // For non-authenticated users, use the old approach
                  await prefs.setString('name', newName);
                }
                
                // Update AuthService
                await authService.updateUserName(newName);
                
                // Update parent state via callback
                widget.onNameUpdated(newName);
                
                // Close the dialog
                Navigator.of(context).pop();
                
                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Name updated successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context, AuthService authService) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.account_circle, color: Color(0xFF6B46C1)),
              SizedBox(width: 8),
              Text('Edit Profile'),
            ],
          ),
          value: 'edit_profile',
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.settings, color: Colors.blue),
              SizedBox(width: 8),
              Text('Settings'),
            ],
          ),
          value: 'settings',
        ),
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 8),
              Text('Sign Out'),
            ],
          ),
          value: 'sign_out',
        ),
      ],
      elevation: 8.0,
    ).then((value) {
      if (value == null) return;
      
      switch (value) {
        case 'edit_profile':
          _showEditProfileDialogFromContent(context, authService);
          break;
        case 'settings':
          // Navigate to settings tab
          if (context.findAncestorStateOfType<_HomeScreenState>() != null) {
            context.findAncestorStateOfType<_HomeScreenState>()!.setState(() {
              context.findAncestorStateOfType<_HomeScreenState>()!._selectedIndex = 4;
            });
          }
          break;
        case 'sign_out':
          _showSignOutConfirmation(context, authService);
          break;
      }
    });
  }

  // Method to show edit profile dialog
  void _showEditProfileDialog(BuildContext context, AuthService authService) async {
    final TextEditingController nameController = TextEditingController();
                            nameController.text = widget.savedName.isNotEmpty ? widget.savedName : '';

    // Get the name from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('name');
    if (savedName != null && savedName.isNotEmpty) {
      nameController.text = savedName;
    }

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding: EdgeInsets.fromLTRB(24, 24, 24, 8),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.person, color: Colors.blue, size: 24),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(24, 20, 24, 24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Name',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter your name',
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                // Save to SharedPreferences based on authentication status
                if (authService.isAuthenticated && authService.userDetails != null) {
                  // For authenticated users, save per user ID
                  final userId = authService.userDetails!.id;
                  await prefs.setString('name_$userId', newName);
                } else {
                  // For non-authenticated users, use the old approach
                  await prefs.setString('name', newName);
                }
                
                // Update AuthService
                await authService.updateUserName(newName);
                
                // Update parent state via callback
                widget.onNameUpdated(newName);
                
                // Show success message
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Name updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSignOutConfirmation(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Sign Out'),
        content: Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await authService.signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Signed out successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _generateMedicineDataHash(List<Map<String, dynamic>> medicineData) {
    try {
      // Create a simplified representation for hashing with safe JSON conversion
      final List<Map<String, String>> simplified = [];
      
      for (var med in medicineData) {
        // Create a simplified map with only string values
        Map<String, String> simpleMed = {
          'id': _safeToString(med['id']),
          'name': _safeToString(med['name']),
          'time': _safeToString(med['time']),
          'dosage': _safeToString(med['dosage']),
        };
        
        simplified.add(simpleMed);
      }
      
      // Sort by ID to ensure consistent order
      simplified.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
      
      // Use hashCode as a simple hash
      final jsonString = jsonEncode(simplified);
      return jsonString.hashCode.toString();
    } catch (e) {
      print('Error generating medicine data hash: $e');
      return DateTime.now().millisecondsSinceEpoch.toString();
    }
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
}

class PrescriptionReviewDialog extends StatelessWidget {
  final Map<String, dynamic> prescriptionData;
  final VoidCallback onSaveAll;
  final Function(Map<String, dynamic>) onEditIndividual;

  PrescriptionReviewDialog({
    required this.prescriptionData,
    required this.onSaveAll,
    required this.onEditIndividual,
  });

  String _formatMedicineDetails(Map<String, dynamic> medicine) {
    final timing = medicine['mappedTiming'] ?? 'Not specified';
    final frequency = medicine['mappedFrequency'] ?? 'Once Daily';
    final time = medicine['mappedTime'] ?? '08:00 AM';
    final duration = medicine['duration'] ?? 'Not specified';
    
    // Only include dosage if it's available
    final dosage = medicine['dosage'] != null ? '${medicine['dosage']}\n' : '';
    
    return '$dosage$frequency - $timing\nTime: $time\nDuration: $duration';
  }

  @override
  Widget build(BuildContext context) {
    final medicines = prescriptionData['medicines'] as List;
    
    return AlertDialog(
      title: Text('Review Prescription'),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Found ${medicines.length} medicines:'),
            SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: medicines.length,
                separatorBuilder: (context, index) => Divider(),
                itemBuilder: (context, index) {
                  final medicine = medicines[index];
                  return ListTile(
                    title: Text(medicine['name'] ?? ''),
                    subtitle: Text(_formatMedicineDetails(medicine)),
                    trailing: IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () {
                        // Ensure all mapped values are included
                        final enrichedMedicine = <String, dynamic>{
                          ...Map<String, dynamic>.from(medicine),
                          'prescriptionData': prescriptionData,
                          'isFromPrescription': true,
                          'timing': medicine['mappedTiming'] ?? medicine['timing'],
                          'frequency': medicine['mappedFrequency'],
                          'time': medicine['mappedTime'],
                          'foodInstructions': medicine['mappedFoodInstructions'],
                        };
                        onEditIndividual(enrichedMedicine);
                      },
                    ),
                    isThreeLine: true,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: onSaveAll,
          child: Text('Save All'),
        ),
      ],
    );
  }
}

class CalendarCard extends StatefulWidget {
  final Function(DateTime) onDateSelected;
  final DateTime selectedDate;
  
  CalendarCard({
    required this.onDateSelected,
    required this.selectedDate,
  });
  
  @override
  _CalendarCardState createState() => _CalendarCardState();
}

class _CalendarCardState extends State<CalendarCard> {
  int selectedIndex = 1;
  final List<Map<String, dynamic>> dates = [];
  Map<String, bool> datesWithMedicine = {};

  @override
  void initState() {
    super.initState();
    _initDates();
    _loadMedicineDates();
  }

  void _initDates() {
    // Initialize dates based on current date
    DateTime now = DateTime.now();
    dates.clear();
    
    // Find the index of the selected date
    int selectedDateIndex = 1; // Default to today (index 1)
    
    for (int i = -1; i < 5; i++) {
      DateTime date = now.add(Duration(days: i));
      dates.add({
        "day": DateFormat('EEEE').format(date),
        "date": DateFormat('d').format(date),
        "fullDate": date,
      });
      
      // Check if this date matches the selected date
      if (DateFormat('yyyy-MM-dd').format(date) == 
          DateFormat('yyyy-MM-dd').format(widget.selectedDate)) {
        selectedDateIndex = i + 1; // +1 because we start at -1
      }
    }
    
    // Set the selected index
    setState(() {
      selectedIndex = selectedDateIndex;
    });
  }
  
  @override
  void didUpdateWidget(CalendarCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // If the selected date changed, update the UI
    if (oldWidget.selectedDate != widget.selectedDate) {
      _initDates();
    }
  }
  
  Future<void> _loadMedicineDates() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.userDetails == null) return;
      
      // Get today's date and the 7 days around it
      final DateTime now = DateTime.now();
      final List<String> dateStringsToCheck = [];
      
      // Generate a list of dates to check (past 1 day and future 5 days)
      for (int i = -1; i < 5; i++) {
        final date = now.add(Duration(days: i));
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        dateStringsToCheck.add(dateStr);
      }
      
      // Get the current schedule document
      final scheduleDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(authService.userDetails!.id)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        if (mounted) {
          setState(() {
            datesWithMedicine = {};
          });
        }
        return;
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
      
      // Create a map to hold medicine counts for each date
      Map<String, bool> medicineMap = {};
      
      // Process each medicine in the schedule
      for (var entry in medicines.entries) {
        final medicineData = entry.value as Map<String, dynamic>? ?? {};
        final scheduleDataList = List<Map<String, dynamic>>.from(medicineData['scheduleData'] ?? []);
        
        // Get excluded dates for this medicine
        List<String> excludedDates = [];
        if (medicineData.containsKey('excludedDates') && medicineData['excludedDates'] is List) {
          excludedDates = List<String>.from((medicineData['excludedDates'] as List).where((item) => item != null).cast<String>());
        }
        
        // Check each schedule entry
        for (var schedule in scheduleDataList) {
          final scheduleDate = schedule['date'] as String?;
          
          if (scheduleDate != null && dateStringsToCheck.contains(scheduleDate)) {
            // Only mark if not excluded
            if (!excludedDates.contains(scheduleDate)) {
              medicineMap[scheduleDate] = true;
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          datesWithMedicine = medicineMap;
        });
      }
    } catch (e) {
      print('Error loading medicine dates: $e');
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only reload medicine dates if we have a valid context and mounted
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      _loadMedicineDates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        itemBuilder: (context, index) {
          bool isSelected = index == selectedIndex;
          DateTime fullDate = dates[index]['fullDate'];
          String dateStr = DateFormat('yyyy-MM-dd').format(fullDate);
          bool hasMedicine = datesWithMedicine[dateStr] == true;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                selectedIndex = index;
              });
              // Call the callback with the selected date
              widget.onDateSelected(dates[index]['fullDate']);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                children: [
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: CircleAvatar(
                        radius: 4,
                        backgroundColor: Colors.red[400],
                      ),
                    )
                  else
                    SizedBox(height: 8),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dates[index]['date'],
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.lightBlue
                                      : Colors.red[400],
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                dates[index]['day'].substring(0, 3), // Show only first 3 characters
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Remove the green dot indicator
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
