import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart' as login_screen;
import 'help_support_screen.dart';
import 'privacy_security_screen.dart';
import 'adherence_tracking_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsScreen extends StatefulWidget {
  final Function(String)? onNameUpdated;
  
  const SettingsScreen({Key? key, this.onNameUpdated}) : super(key: key);
  
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final NotificationService _notificationService = NotificationService();
  Map<String, dynamic> _notificationSettings = {};
  String _savedName = '';
  
  // Store the subscription to properly dispose of it later
  late StreamSubscription<Map<String, dynamic>> _settingsSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
    _loadSavedName();
    
    // Listen for updates to settings from the notification service
    _settingsSubscription = _notificationService.onSettingsChanged.listen((settings) {
      if (settings['event'] == 'customSoundUpdated') {
        _loadNotificationSettings();
      }
    });
  }

  @override
  void dispose() {
    // Clean up any listeners or resources
    _settingsSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadNotificationSettings() async {
    final settings = await _notificationService.getNotificationSettings();
    setState(() {
      _notificationSettings = settings;
    });
  }

  // Enhanced share method with native Android share sheet
  Future<bool> _shareContent(String text, String subject) async {
    const platform = MethodChannel('share_channel');
    
    try {
      // Use native Android share intent
      final result = await platform.invokeMethod('share', {
        'text': text,
        'subject': subject,
      });
      return result == true;
    } catch (e) {
      print('Native share failed: $e');
    }
    
    // Fallback to specific apps if native sharing fails
    return await _fallbackShare(text, subject);
  }

  Future<bool> _fallbackShare(String text, String subject) async {
    // Try to open the system share dialog using a simple approach
    try {
      // Use a simple share intent that should work on most Android devices
      final shareIntent = 'intent://send?text=${Uri.encodeComponent(text)}#Intent;action=android.intent.action.SEND;type=text/plain;package=com.whatsapp;end';
      final uri = Uri.parse(shareIntent);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('WhatsApp intent failed: $e');
    }
    
    // Try email as a simple fallback
    try {
      final emailUri = Uri.parse('mailto:?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('Email failed: $e');
    }
    
    // Try SMS as another simple fallback
    try {
      final smsUri = Uri.parse('sms:?body=${Uri.encodeComponent(text)}');
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('SMS failed: $e');
    }
    
    return false;
  }

  Future<void> _loadSavedName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final authService = Provider.of<AuthService>(context, listen: false);
      
      String? savedName;
      
      if (authService.isAuthenticated && authService.userDetails != null) {
        // For authenticated users, load per user ID
        final userId = authService.userDetails!.id;
        savedName = prefs.getString('name_$userId');
        
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
              print('Loaded name from Firebase in settings: $savedName');
            }
          } catch (e) {
            print('Error loading name from Firebase in settings: $e');
          }
        }
      } else {
        // For non-authenticated users, use the old approach
        savedName = prefs.getString('name');
      }
      
      if (savedName != null && savedName.isNotEmpty) {
        setState(() {
          _savedName = savedName!; // Use null assertion operator since we've already checked for null
        });
      }
    } catch (e) {
      print('Error loading saved name: $e');
    }
  }

  Future<void> _updateSetting(String key, dynamic value) async {
    // Immediately update local state for instant UI feedback
    setState(() {
      _notificationSettings[key] = value;
    });
    await _notificationService.updateNotificationSetting(key, value);
    // Wait a short delay before reloading settings to ensure native side is updated
    await Future.delayed(Duration(milliseconds: 200));
    await _loadNotificationSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF6B46C1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.settings, color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Notifications Section
            Text(
              'Notifications',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildSettingsToggle(
                    'Full Screen Alerts',
                    'Show full-screen medication alerts',
                    _notificationSettings['fullScreen'] ?? true, // Default to true
                    (value) async {
                      await _updateSetting(NotificationService.fullScreenKey, value);
                      setState(() {
                        _notificationSettings['fullScreen'] = value; // Reflect the toggle change
                      });
                    },
                  ),
                  Divider(),
                  _buildSettingsToggle(
                    'Vibration',
                    'Vibrate for medication reminders',
                    _notificationSettings[NotificationService.vibrationKey] ?? true,
                    (value) async {
                      await _updateSetting(NotificationService.vibrationKey, value);
                    },
                  ),
                  Divider(),
                  _buildSettingsToggle(
                    'Sound Alerts',
                    'Play sound for reminders',
                    _notificationSettings[NotificationService.soundKey] ?? true,
                    (value) async {
                      await _updateSetting(NotificationService.soundKey, value);
                    },
                  ),
                  Divider(),
                  _buildSettingsToggle(
                    'Use Default Alarm Sound',
                    'Use system alarm sound',
                    _notificationSettings[NotificationService.useDefaultAlarmKey] ?? true,
                    (value) async {
                      await _updateSetting(NotificationService.useDefaultAlarmKey, value);
                    },
                  ),
                  Divider(),
                  _buildSnoozeDurationSetting(),
                  if (!(_notificationSettings[NotificationService.useDefaultAlarmKey] ?? true)) ...[
                    Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      title: Row(
                        children: [
                          Text('Custom Sound', style: TextStyle(fontWeight: FontWeight.w500)),
                          SizedBox(width: 8),
                          if (_notificationSettings['customSoundPath'] != null && 
                              _notificationSettings['customSoundPath'].toString().isNotEmpty)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(
                                'Selected',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 4),
                          Text(
                            _notificationSettings['customSoundPath'] != null && 
                            _notificationSettings['customSoundPath'].toString().isNotEmpty
                              ? _getFileNameFromPath(_notificationSettings['customSoundPath'].toString())
                              : 'No custom sound selected',
                            style: TextStyle(
                              color: _notificationSettings['customSoundPath'] != null && 
                                    _notificationSettings['customSoundPath'].toString().isNotEmpty
                                  ? Colors.black87
                                  : Colors.grey.shade500,
                            ),
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.info_outline, size: 12, color: Colors.grey.shade600),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Select an audio file from your device to use as your medication reminder',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: ElevatedButton.icon(
                        icon: Icon(Icons.music_note, color: Colors.white, size: 16),
                        label: Text('Browse', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade400,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: Size(80, 36),
                        ),
                        onPressed: () async {
                          await _pickCustomSoundWithPermission();
                        },
                      ),
                      onTap: () async {
                        await _pickCustomSoundWithPermission();
                      },
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: 30),
            
            // Account Section
            Text(
              'Account',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Consumer<AuthService>(
                    builder: (context, authService, child) {
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade400,
                          backgroundImage: authService.user?.photoURL != null
                              ? NetworkImage(authService.user!.photoURL!)
                              : null,
                          child: authService.user?.photoURL == null
                              ? Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        title: Text(
                          _savedName.isNotEmpty ? _savedName : '',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(authService.user?.email ?? 'user@example.com'),
                        trailing: Icon(Icons.edit, color: Colors.blue.shade400),
                        onTap: () {
                          _showEditProfileDialog(context, authService);
                        },
                      );
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.qr_code),
                    title: Text('My Share Code'),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Consumer<AuthService>(
                          builder: (context, auth, _) => FutureBuilder<String>(
                            future: auth.generateShareCode(),
                            initialData: null,
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return Text('Error loading code',
                                    style: TextStyle(color: Colors.red));
                              }
                              
                              if (snapshot.connectionState == ConnectionState.waiting && snapshot.data == null) {
                                return Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                );
                              }
                              
                              return Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      snapshot.data ?? 'Loading...',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Share this code with caretakers via WhatsApp, email, or other apps to allow them to access your medication schedule.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Share via WhatsApp, Email, or other apps',
                          child: IconButton(
                            icon: Icon(Icons.share, color: Colors.green.shade600),
                            onPressed: () async {
                              final BuildContext currentContext = context;
                              final scaffoldMessenger = ScaffoldMessenger.of(context);
                              final authService = Provider.of<AuthService>(context, listen: false);
                              
                              try {
                                String shareCode = await authService.generateShareCode();
                                
                                String shareText = 'My Medication Share Code: $shareCode\n\n'
                                    'Use this code in the MedicFood App to manage my Medication Schedule.\n\n'
                                    'Download the app and use this code to view my medications.';
                                
                                // This will show the native Android share window
                                bool shared = await _shareContent(shareText, 'Medication Share Code');
                                
                                if (mounted) {
                                  if (shared) {
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Row(
                                          children: [
                                            Icon(Icons.check_circle, color: Colors.white),
                                            SizedBox(width: 8),
                                            Text('Share completed'),
                                          ],
                                        ),
                                        backgroundColor: Colors.green.shade600,
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } else {
                                    // Copy to clipboard as final fallback
                                    await Clipboard.setData(ClipboardData(text: shareText));
                                    scaffoldMessenger.showSnackBar(
                                      SnackBar(
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.content_copy, color: Colors.white),
                                                SizedBox(width: 8),
                                                Text('Share code copied to clipboard'),
                                              ],
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'Paste it in any messaging app',
                                              style: TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        backgroundColor: Colors.blue.shade600,
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                                
                              } catch (e) {
                                print('Error sharing code: $e');
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(Icons.error, color: Colors.white),
                                          SizedBox(width: 8),
                                          Text('Failed to share code. Please try again.'),
                                        ],
                                      ),
                                      backgroundColor: Colors.red.shade600,
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        Tooltip(
                          message: 'Copy to clipboard',
                          child: IconButton(
                            icon: Icon(Icons.copy, color: Colors.blue.shade400),
                            onPressed: () async {
                            // Capture the scaffold messenger and context safely
                            final scaffoldMessenger = ScaffoldMessenger.of(context);
                            final BuildContext currentContext = context;
                            
                            final authService = Provider.of<AuthService>(context, listen: false);
                            try {
                              String shareCode = await authService.generateShareCode();
                              await Clipboard.setData(ClipboardData(text: shareCode));
                              
                              // Use a post-frame callback to safely show the snackbar
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.check_circle, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text('Share code copied to clipboard'),
                                      ],
                                    ),
                                    backgroundColor: Colors.green.shade600,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                              });
                            } catch (e) {
                              // Use a post-frame callback to safely show the error snackbar
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        Icon(Icons.error, color: Colors.white),
                                        SizedBox(width: 8),
                                        Text('Failed to generate share code'),
                                      ],
                                    ),
                                    backgroundColor: Colors.red.shade600,
                                  ),
                                );
                              }
                              });
                            }
                          },
                        ),
                        ),
                      ],
                    ),
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.privacy_tip, color: Colors.green.shade400),
                    title: Text('Privacy & Security'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => PrivacySecurityScreen()),
                      );
                    },
                  ),
                  Divider(),
                  ListTile(
                    leading: Icon(Icons.help, color: Colors.orange.shade400),
                    title: Text('Help & Support'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HelpSupportScreen()),
                      );
                    },
                  ),
                  Divider(),
                  Consumer<AuthService>(
                    builder: (context, authService, child) {
                      return ListTile(
                        leading: Icon(Icons.logout, color: Colors.red.shade400),
                        title: Text('Sign Out'),
                        onTap: () async {
                          // Store auth service reference before async operation
                          final auth = authService;
                          final navigatorContext = context;
                          
                          await auth.signOut();
                          
                          // Check if widget is still mounted before navigating
                          if (!mounted) return;
                          
                          Navigator.pushAndRemoveUntil(
                            navigatorContext,
                            MaterialPageRoute(builder: (context) => login_screen.LoginScreen()),
                            (route) => false,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),
            Text(
              'Health & Tracking',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.track_changes, color: Color(0xFF5E4B8B)),
                    title: Text('Adherence Tracking'),
                    subtitle: Text('Track your medication compliance and adherence rates'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) =>  AdherenceTrackingScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            SizedBox(height: 30),
            Text(
              'App Info',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.info, color: Colors.blue.shade400),
                    title: Text('App Version'),
                    subtitle: Text('1.0.0'),
                  ),
                  Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.rate_review, color: Colors.purple.shade400),
                    title: Text('Rate App'),
                    trailing: Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      // Rate app handler
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSettingsToggle(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.red.shade400,
      ),
    );
  }

  String _getFileNameFromPath(String path) {
    try {
      // For Android content:// URIs, we just show a friendly name
      if (path.startsWith('content://')) {
        return 'Custom sound selected';
      }
      
      // For file paths, extract the file name
      final segments = path.split('/');
      final fileName = segments.last;
      
      // Limit the length for display
      if (fileName.length > 30) {
        return '${fileName.substring(0, 27)}...';
      }
      return fileName;
    } catch (e) {
      return 'Custom sound';
    }
  }

  /// Handle custom sound picking with proper permission handling
  Future<void> _pickCustomSoundWithPermission() async {
    try {
      final result = await _notificationService.pickCustomSound();
      
      if (!result) {
        // Permission was denied, show a dialog
        if (!mounted) return;
        
        // Capture the context for safety
        final BuildContext currentContext = context;
        
        // Use a post-frame callback to ensure we're in a safe frame to show the dialog
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
        showDialog(
              context: currentContext,
              builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 12),
                Text('Permission Required'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage permission is required to select custom sound files for medication reminders.',
                  style: TextStyle(fontSize: 14),
                ),
                SizedBox(height: 16),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Please grant storage permission in app settings.',
                          style: TextStyle(
                            color: Colors.blue.shade900,
                            fontSize: 13,
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
                    onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                      Navigator.of(dialogContext).pop();
                  _notificationService.openAppSettings();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: Text('Open Settings'),
              ),
            ],
          ),
        );
          }
        });
      }
    } catch (e) {
      print('Error picking custom sound: $e');
      
      if (!mounted) return;
      
      // Safely show snackbar without relying on context in a possibly deactivated widget
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error selecting sound file'),
          backgroundColor: Colors.red,
        ),
      );
        }
      });
    }
  }
  
  // Method to show edit profile dialog
  void _showEditProfileDialog(BuildContext context, AuthService authService) async {
    final TextEditingController nameController = TextEditingController();
    nameController.text = _savedName.isNotEmpty ? _savedName : '';

    // Capture a strong reference to the context
    final BuildContext currentContext = context;

    // Get the name from SharedPreferences or Firebase
    final prefs = await SharedPreferences.getInstance();
    String? savedName;
    
    if (authService.isAuthenticated && authService.userDetails != null) {
      // For authenticated users, load per user ID
      final userId = authService.userDetails!.id;
      savedName = prefs.getString('name_$userId');
      
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
            print('Loaded name from Firebase in edit dialog: $savedName');
          }
        } catch (e) {
          print('Error loading name from Firebase in edit dialog: $e');
        }
      }
    } else {
      // For non-authenticated users, use the old approach
      savedName = prefs.getString('name');
    }
    
    if (savedName != null && savedName.isNotEmpty) {
      nameController.text = savedName;
    }

    // Safely check if mounted before showing dialog
    if (!mounted) return;
    
    // Use post-frame callback to ensure we're in a safe render phase
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog(
          context: currentContext,
          builder: (dialogContext) => AlertDialog(
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
                onPressed: () => Navigator.of(dialogContext).pop(),
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
                
                // Update local state
                setState(() {
                  _savedName = newName;
                });
                
                // Notify parent widget about the name update
                if (mounted && widget.onNameUpdated != null) {
                  widget.onNameUpdated!(newName);
                }
                
                    // Close the dialog
                    Navigator.of(dialogContext).pop();
                    
                    // Show success message safely
                    if (mounted) {
                      // Get scaffold messenger safely
                      final scaffoldMessenger = ScaffoldMessenger.of(currentContext);
                      
                      // Use post callback for UI updates
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                          scaffoldMessenger.showSnackBar(
                    SnackBar(
                      content: Text('Name updated successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                        }
                      });
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
    });
  }

  Widget _buildSnoozeDurationSetting() {
    return ListTile(
      title: Text(
        'Snooze Duration',
        style: TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        'Select the duration for snooze',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
      ),
      trailing: DropdownButton<int>(
        value: _notificationSettings[NotificationService.snoozeDurationKey] ?? 5,
        items: [
          DropdownMenuItem<int>(value: 5, child: Text('5 minutes')),
          DropdownMenuItem<int>(value: 10, child: Text('10 minutes')),
          DropdownMenuItem<int>(value: 15, child: Text('15 minutes')),
          DropdownMenuItem<int>(value: 30, child: Text('30 minutes')),
        ],
        onChanged: (value) async {
          await _updateSetting(NotificationService.snoozeDurationKey, value);
          setState(() {
            _notificationSettings[NotificationService.snoozeDurationKey] = value;
          });
        },
      ),
    );
  }


}
