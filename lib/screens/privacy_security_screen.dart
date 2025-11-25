import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:convert';
import 'package:intl/intl.dart';

class PrivacySecurityScreen extends StatefulWidget {
  @override
  _PrivacySecurityScreenState createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _dataCollection = true;
  bool _analyticsEnabled = true;
  bool _crashReporting = true;
  bool _allowNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  Future<void> _loadPrivacySettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _dataCollection = prefs.getBool('data_collection') ?? true;
      _analyticsEnabled = prefs.getBool('analytics_enabled') ?? true;
      _crashReporting = prefs.getBool('crash_reporting') ?? true;
      _allowNotifications = prefs.getBool('allow_notifications') ?? true;
    });
  }

  Future<void> _savePrivacySetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Privacy & Security',
          style: TextStyle(
            color: Colors.black, 
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6B46C1), Color(0xFF5E4B8B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Color(0xFF6B46C1).withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.privacy_tip, color: Colors.white, size: 24),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Privacy Section
            _buildSection(
              title: 'Privacy Settings',
              icon: Icons.privacy_tip,
              children: [
                _buildToggleTile(
                  'Data Collection',
                  'Allow app to collect usage data to improve your experience',
                  _dataCollection,
                  (value) {
                    setState(() {
                      _dataCollection = value;
                    });
                    _savePrivacySetting('data_collection', value);
                  },
                ),
                _buildToggleTile(
                  'Analytics',
                  'Help us improve by sharing anonymous usage statistics',
                  _analyticsEnabled,
                  (value) {
                    setState(() {
                      _analyticsEnabled = value;
                    });
                    _savePrivacySetting('analytics_enabled', value);
                  },
                ),
                _buildToggleTile(
                  'Crash Reporting',
                  'Automatically report app crashes to help fix issues',
                  _crashReporting,
                  (value) {
                    setState(() {
                      _crashReporting = value;
                    });
                    _savePrivacySetting('crash_reporting', value);
                  },
                ),

              ],
            ),

            SizedBox(height: 24),

            // Data Management Section
            _buildSection(
              title: 'Data Management',
              icon: Icons.storage,
              children: [
                _buildActionTile(
                  'Export My Data',
                  'Download a copy of your personal data',
                  Icons.download,
                  () => _exportData(),
                ),

                _buildActionTile(
                  'Privacy Policy',
                  'Read our privacy policy and data handling practices',
                  Icons.description,
                  () => _showPrivacyPolicy(context),
                ),
                _buildActionTile(
                  'Terms of Service',
                  'View our terms of service and user agreement',
                  Icons.gavel,
                  () => _showTermsOfService(context),
                ),
              ],
            ),

            SizedBox(height: 24),

            // Information Section
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue.shade700),
                      SizedBox(width: 8),
                      Text(
                        'Your Privacy Matters',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'We are committed to protecting your privacy and personal information. All data is encrypted and stored securely. You have full control over your data and can modify these settings at any time.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 4),
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
                  color: Color(0xFF5E4B8B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Color(0xFF5E4B8B), size: 20),
              ),
              SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }

  Widget _buildToggleTile(
    String title,
    String subtitle,
    bool value,
    Function(bool) onChanged,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            height: 1.3,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Color(0xFF5E4B8B),
        ),
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF5E4B8B).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Color(0xFF5E4B8B), size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            height: 1.3,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
        onTap: onTap,
      ),
    );
  }

  void _exportData() async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5E4B8B)),
                ),
                SizedBox(height: 16),
                Text(
                  'Preparing your data...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      );

      // Get current user
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Navigator.of(context).pop(); // Close loading dialog
        _showErrorDialog('No user logged in');
        return;
      }

      // Collect all user data
      final exportData = await _collectUserData(user.uid);

      // Generate filename with timestamp
      final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
      final filename = 'medic_app_data_$timestamp.json';

      // Get app documents directory
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      // Write data to file
      await file.writeAsString(jsonEncode(exportData));

      // Close loading dialog
      Navigator.of(context).pop();

      // Show success dialog with file info
      _showExportSuccessDialog(context, file.path, filename);

    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      _showErrorDialog('Failed to export data: $e');
    }
  }

  Future<Map<String, dynamic>> _collectUserData(String userId) async {
    final firestore = FirebaseFirestore.instance;
    final prefs = await SharedPreferences.getInstance();

    // Get user profile data
    final userDoc = await firestore.collection('users').doc(userId).get();
    final userData = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : <String, dynamic>{};

    // Get all medicines from the schedule
    final scheduleDoc = await firestore
        .collection('users')
        .doc(userId)
        .collection('medicine_schedules')
        .doc('current_schedule')
        .get();
    
    List<Map<String, dynamic>> medicines = [];
    if (scheduleDoc.exists) {
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicinesMap = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
      
      medicines = medicinesMap.entries.map((entry) {
        final medicineId = entry.key;
        final medicineData = Map<String, dynamic>.from(entry.value);
        medicineData['id'] = medicineId;
        return medicineData;
      }).toList();
    }

    // Get notification settings
    final notificationSettings = {
      'data_collection': prefs.getBool('data_collection') ?? true,
      'analytics_enabled': prefs.getBool('analytics_enabled') ?? true,
      'crash_reporting': prefs.getBool('crash_reporting') ?? true,
      'share_data_caretaker': prefs.getBool('share_data_caretaker') ?? true,
      'show_medication_history': prefs.getBool('show_medication_history') ?? true,
      'allow_notifications': prefs.getBool('allow_notifications') ?? true,
    };

    // Get app settings
    final appSettings = {
      'fullScreen': prefs.getBool('fullScreen') ?? true,
      'vibration': prefs.getBool('vibration') ?? true,
      'sound': prefs.getBool('sound') ?? true,
      'useDefaultAlarm': prefs.getBool('useDefaultAlarm') ?? true,
      'customSoundPath': prefs.getString('customSoundPath'),
    };

    // Compile export data
    final exportData = {
      'exportInfo': {
        'exportDate': DateTime.now().toIso8601String(),
        'appVersion': '1.0.0',
        'userId': userId,
      },
      'userProfile': {
        'name': userData?['name'] ?? '',
        'email': userData?['email'] ?? '',
        'photoUrl': userData?['photoUrl'] ?? '',
        'shareCode': userData?['shareCode'] ?? '',
        'createdAt': userData?['createdAt'] ?? '',
      },
      'medicines': medicines,
      'privacySettings': notificationSettings,
      'appSettings': appSettings,
      'statistics': {
        'totalMedicines': medicines.length,
        'exportDate': DateTime.now().toIso8601String(),
      },
    };

    return exportData;
  }

  void _showExportSuccessDialog(BuildContext context, String filePath, String filename) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Export Successful', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your data has been exported successfully!',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File saved as:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      filename,
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Location: ${filePath.split('/').take(filePath.split('/').length - 1).join('/')}',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Text(
                'The exported file contains:',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              SizedBox(height: 8),
              _buildExportItem('User profile information'),
              _buildExportItem('All medication data'),
              _buildExportItem('Privacy settings'),
              _buildExportItem('App preferences'),
              _buildExportItem('Usage statistics'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildExportItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check, size: 16, color: Colors.green),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red),
              SizedBox(width: 8),
              Text('Export Failed', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Text(
            message,
            style: TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }



  void _showPrivacyPolicy(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.privacy_tip, color: Color(0xFF5E4B8B)),
              SizedBox(width: 8),
              Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Our privacy policy ensures that your personal information is protected and used responsibly. We collect only necessary data to provide you with the best medication management experience. Your data is encrypted and stored securely.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showTermsOfService(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.gavel, color: Color(0xFF5E4B8B)),
              SizedBox(width: 8),
              Text('Terms of Service', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'By using this app, you agree to our terms of service. The app is designed to help with medication management but should not replace professional medical advice. Always consult with healthcare professionals for medical decisions.',
              style: TextStyle(fontSize: 14),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
} 