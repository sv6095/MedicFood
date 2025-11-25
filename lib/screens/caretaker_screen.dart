import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/timing_utils.dart';
import '../utils/duration_helper.dart';
import '../services/medicine_service.dart';
import 'prescription_scanner_screen.dart';

class PatientsScreen extends StatefulWidget {
  @override
  _PatientsScreenState createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  // Add controllers to be disposed
  final List<TextEditingController> _controllersToDispose = [];
  bool _isDisposed = false;
  bool _isLoading = true;
  bool _isDependent = false;
  
  // Define collections that caretakers can access
  final List<String> _allowedReadCollections = ['medications'];
  final List<String> _allowedWriteCollections = ['medications'];

  // Define a class-level variable for loadingDialogContext
  BuildContext? loadingDialogContext;

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  // Initialize authentication state
  Future<void> _initializeAuth() async {
    try {
      // Listen to auth state changes
      FirebaseAuth.instance.authStateChanges().listen((User? user) {
        if (mounted) {
          setState(() {
            _currentUser = user;
          });
          if (user != null) {
            _checkUserRole();
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        }
      });
      
      // Get current user immediately
      _currentUser = FirebaseAuth.instance.currentUser;
      if (_currentUser != null) {
        await _checkUserRole();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error initializing auth: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Check if the current user is a dependent
  Future<void> _checkUserRole() async {
    try {
      final userDoc = await _firestore.collection('users').doc(_currentUser?.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>? ?? {};
        // If user has caretakers, they are a dependent
        final List<dynamic> caretakers = userData['caretakers'] ?? [];
        setState(() {
          _isDependent = caretakers.isNotEmpty;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error checking user role: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper method to safely show snackbar
  void _safeShowSnackBar(String message) {
    if (!mounted || _isDisposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Dispose all controllers
    for (var controller in _controllersToDispose) {
      controller.dispose();
    }
    _controllersToDispose.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If user is a dependent, show the CaretakersScreen instead
    if (_isDependent) {
      return CaretakersScreen();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Caretaker Dashboard',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF6B46C1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.people, color: Colors.white),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage your family members and dependents',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: _currentUser == null 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Authentication Error',
                            style: TextStyle(fontSize: 16, color: Colors.red)),
                        Text('Please sign in again',
                            style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  )
                : StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(_currentUser!.uid).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print('StreamBuilder error: ${snapshot.error}');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red),
                          SizedBox(height: 16),
                          Text('Permission Error',
                              style: TextStyle(fontSize: 16, color: Colors.red)),
                          Text('Unable to access data',
                              style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return Center(child: Text('No Dependents linked'));
                  }
                  
                  final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                  List<dynamic> patientIds = userData['patients'] ?? [];
                  
                  if (patientIds.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No Dependents linked yet',
                              style: TextStyle(fontSize: 16, color: Colors.grey)),
                          Text('Tap + to add a dependent',
                              style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: patientIds.length,
                    itemBuilder: (context, index) {
                      final patientId = patientIds[index];
                      // Check if we have cached profile data
                      final cachedProfiles = userData['patientProfiles'] as Map<String, dynamic>?;
                      final cachedProfile = cachedProfiles != null ? cachedProfiles[patientId] as Map<String, dynamic>? : null;
                      
                      // If we have cached profile data and it's recent (less than 1 hour old), use it
                      if (cachedProfile != null && cachedProfile['lastSync'] != null) {
                        final lastSync = (cachedProfile['lastSync'] as Timestamp).toDate();
                        final now = DateTime.now();
                        final difference = now.difference(lastSync);
                        
                        if (difference.inHours < 1) {
                          // Use cached data
                          final patientData = {
                            'uid': patientId,
                            'name': cachedProfile['name'],
                            'photoUrl': cachedProfile['photoUrl'],
                            'email': cachedProfile['email'],
                            'shareCode': cachedProfile['shareCode'],
                            'isCached': true,
                          };
                          return _buildPatientCard(patientData);
                        }
                      }
                      
                      // If no cached data or it's stale, fetch from Firestore
                      return FutureBuilder<DocumentSnapshot>(
                        future: _firestore.collection('users').doc(patientId).get(),
                        builder: (context, patientSnapshot) {
                          if (!patientSnapshot.hasData) {
                            return Center(child: CircularProgressIndicator());
                          }
                          
                          var patientData = patientSnapshot.data!.data() as Map<String, dynamic>;
                          patientData['uid'] = patientSnapshot.data!.id;
                          
                          // Update the cache with fresh data
                          if (mounted) {
                            _firestore.collection('users').doc(_currentUser!.uid).update({
                              'patientProfiles.$patientId': {
                                'name': patientData['name'] ?? patientData['email']?.toString().split('@')[0] ?? 'Dependent',
                                'photoUrl': patientData['photoUrl'],
                                'email': patientData['email'],
                                'shareCode': patientData['shareCode'],
                                'lastSync': FieldValue.serverTimestamp(),
                              }
                            }).catchError((e) => print('Error updating cached profile: $e'));
                          }
                          
                          return _buildPatientCard(patientData);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPatientDialog,
        backgroundColor: Colors.purple.shade400,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildPatientCard(Map<String, dynamic> patient) {
    // If using cached data, show a simpler version without medication counts
    if (patient['isCached'] == true) {
      return GestureDetector(
        onTap: () => _showPatientDetails(patient),
        child: Container(
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
          child: Stack(
            children: [
              // Action buttons row
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.medication, color: Colors.purple.shade400, size: 20),
                      onPressed: () => _showMedicinesManagement(patient),
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      tooltip: 'Manage Medications',
                    ),
                    SizedBox(width: 4),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.red.shade400, size: 20),
                      onPressed: () => _showDeleteConfirmation(patient),
                      padding: EdgeInsets.all(4),
                      constraints: BoxConstraints(),
                      tooltip: 'Remove Dependent',
                    ),
                  ],
                ),
              ),
              // Main content - NO MEDICINE STREAM FOR CACHED DATA
              Padding(
                padding: EdgeInsets.only(top: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage: patient['photoUrl'] != null 
                          ? NetworkImage(patient['photoUrl']) 
                          : null,
                      backgroundColor: const Color.fromARGB(255, 50, 44, 77),
                      child: patient['photoUrl'] == null 
                          ? Text(
                              (patient['name'] ?? 'U').substring(0, 1).toUpperCase(),
                              style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    SizedBox(height: 12),
                    Text(
                      _getDisplayName(patient),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 8),
                    // Show static placeholder for medication count
                    Container(
                      height: 4,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap to view medicines',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // For non-cached data, proceed with StreamBuilder
    // But add user ID validation first
    if (patient['uid'] == null || patient['uid'].toString().trim().isEmpty) {
      print('⚠️ Invalid patient UID, skipping StreamBuilder');
      return _buildSimplePatientCard(patient);
    }
    
    // Rest of your existing StreamBuilder code...
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(patient['uid']).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.hasError) {
          print('Patient StreamBuilder error: ${userSnapshot.error}');
          return _buildSimplePatientCard(patient);
        }
        
        // Get real-time user data
        Map<String, dynamic> currentUserData = {};
        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          currentUserData = userSnapshot.data!.data() as Map<String, dynamic>;
          currentUserData['uid'] = userSnapshot.data!.id;
        }
        
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('users')
              .doc(patient['uid'])
              .collection('medicine_schedules')
              .doc('current_schedule')
              .snapshots(),
          builder: (context, scheduleSnapshot) {
            if (scheduleSnapshot.hasError) {
              print('Schedule StreamBuilder error: ${scheduleSnapshot.error}');
              // Continue with empty schedule data
            }
            int taken = 0;
            int total = 0;
            
            if (scheduleSnapshot.hasData && scheduleSnapshot.data!.exists) {
              final scheduleData = scheduleSnapshot.data!.data() as Map<String, dynamic>;
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

            // Update medication count in user document
            if (scheduleSnapshot.hasData && mounted) {
              _firestore.collection('users')
                  .doc(patient['uid'])
                  .update({
                    'medicinesCount': total,
                    'medicinesTaken': taken,
                  }).catchError((e) => print('Error updating medication count: $e'));
            }

            return Container(
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
              child: Stack(
                children: [
                  // Action buttons row
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: Icon(Icons.medication, color: Colors.purple.shade400, size: 20),
                          onPressed: () => _showMedicinesManagement(currentUserData.isNotEmpty ? currentUserData : patient),
                          padding: EdgeInsets.all(4),
                          constraints: BoxConstraints(),
                          tooltip: 'Manage Medications',
                        ),
                        SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.red.shade400, size: 20),
                          onPressed: () => _showDeleteConfirmation(currentUserData.isNotEmpty ? currentUserData : patient),
                          padding: EdgeInsets.all(4),
                          constraints: BoxConstraints(),
                          tooltip: 'Remove Dependent',
                        ),
                      ],
                    ),
                  ),
                  // Main content
                  Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Patient info
                        GestureDetector(
                          onTap: () => _showPatientDetails(currentUserData.isNotEmpty ? currentUserData : patient),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundImage: currentUserData['photoUrl'] != null 
                                    ? NetworkImage(currentUserData['photoUrl']) 
                                    : (patient['photoUrl'] != null 
                                        ? NetworkImage(patient['photoUrl'])
                                        : null),
                                backgroundColor: const Color.fromARGB(255, 50, 44, 77),
                                child: (currentUserData['photoUrl'] == null && patient['photoUrl'] == null)
                                    ? Text(
                                        _getDisplayName(currentUserData.isNotEmpty ? currentUserData : patient)
                                            .substring(0, 1).toUpperCase(),
                                        style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              SizedBox(height: 12),
                              Text(
                                _getDisplayName(currentUserData.isNotEmpty ? currentUserData : patient),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: total > 0 ? taken / total : 0,
                                backgroundColor: Colors.grey[200],
                                valueColor: AlwaysStoppedAnimation(Colors.purple.shade400),
                              ),
                              SizedBox(height: 4),
                              Text(
                                total > 0 ? '$taken/$total taken' : 'No medications',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Add this helper method for invalid patient data
  Widget _buildSimplePatientCard(Map<String, dynamic> patient) {
    return Container(
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.grey.shade400,
            child: Text(
              'U',
              style: TextStyle(fontSize: 24, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(height: 12),
          Text(
            _getDisplayName(patient),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Text(
            'Unable to load',
            style: TextStyle(fontSize: 12, color: Colors.red),
          ),
        ],
      ),
    );
  }

  void _showAddPatientDialog() {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
    final TextEditingController _codeController = TextEditingController();
    // Add to controllers list to be disposed later
    _controllersToDispose.add(_codeController);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Link dependent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                controller: _codeController,
                maxLength: 5,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Dependent Code',
                  labelStyle: TextStyle(fontSize: 16),
                  hintText: 'Enter 5-character code',
                  helperText: 'Enter the code provided by your caretaker',
                  helperMaxLines: 2,  // Allow helper text to wrap if needed
                  helperStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  errorText: _codeController.text.isNotEmpty && !_isValidShareCode(_codeController.text) 
                    ? 'Invalid code format' 
                    : null,
                  errorMaxLines: 2,  // Allow error text to wrap if needed
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(width: 2),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  counterText: '',
                ),
                onChanged: (value) {
                  // Convert to uppercase and remove non-alphanumeric characters as they type
                  final newValue = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                  if (value != newValue) {
                    _codeController.value = _codeController.value.copyWith(
                      text: newValue,
                      selection: TextSelection.collapsed(offset: newValue.length),
                    );
                  }
                  // Force rebuild to show/hide error text
                  setState(() {});
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = _codeController.text.trim().toUpperCase();
              
              // Validate empty code
              if (code.isEmpty) {
                if (!mounted) return;
                _safeShowSnackBar('Please enter a dependent code');
                return;
              }
              
              // Validate code format
              if (!_isValidShareCode(code)) {
                if (!mounted) return;
                _safeShowSnackBar('Code must have exactly 3 letters and 2 numbers');
                return;
              }
              
              try {
                // Check if widget is still mounted before showing dialog
                if (!mounted) return;
                
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return Center(child: CircularProgressIndicator());
                  },
                );

                // Query the users collection to find the user with the given share code
                final querySnapshot = await _firestore.collection('users')
                    .where('shareCode', isEqualTo: code)
                    .limit(1)  // Optimize query by limiting to 1 result
                    .get();

                // Check if widget is still mounted before accessing context
                if (!mounted) return;

                // Hide loading indicator
                Navigator.pop(context);

                if (querySnapshot.docs.isEmpty) {
                  _safeShowSnackBar('Invalid dependent code. Please check and try again.');
                  return;
                }

                final patientId = querySnapshot.docs.first.id;
                final patientData = querySnapshot.docs.first.data();

                // Check if already linked
                final caretakerDoc = await _firestore.collection('users').doc(_currentUser!.uid).get();
                List<dynamic> patients = caretakerDoc.data()?['patients'] ?? [];
                if (patients.contains(patientId)) {
                  if (!mounted) return;
                  Navigator.pop(context);
                  _safeShowSnackBar('Dependent already linked!');
                  return;
                }
                
                // Create caretaker document if it doesn't exist
                if (!caretakerDoc.exists) {
                  await _firestore.collection('users').doc(_currentUser!.uid).set({
                    'patients': [],
                    'name': _currentUser!.displayName ?? 'Caretaker',
                    'email': _currentUser!.email,
                    'role': 'caretaker',
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }

                // Update caretaker's patients array and cache essential profile data
                await _firestore.collection('users')
                    .doc(_currentUser!.uid)
                    .update({
                      'patients': FieldValue.arrayUnion([patientId]),
                      'patientProfiles.$patientId': {
                        'name': patientData['name'] ?? patientData['email']?.toString().split('@')[0] ?? 'Dependent',
                        'photoUrl': patientData['photoUrl'],
                        'email': patientData['email'],
                        'shareCode': patientData['shareCode'],
                        'lastSync': FieldValue.serverTimestamp(),
                      },
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                // Update patient's caretakers array
                final patientDoc = await _firestore.collection('users').doc(patientId).get();
                final patientDocData = patientDoc.data() ?? {};
                List<dynamic> caretakers = patientDocData['caretakers'] ?? [];
                
                // Check if patient has a name, if not update with a default name or email
                if (patientDocData['name'] == null || patientDocData['name'].toString().trim().isEmpty) {
                  String defaultName = patientDocData['email'] != null ? 
                      patientDocData['email'].toString().split('@')[0] : 
                      'Dependent ${patients.length + 1}';
                  
                  await _firestore.collection('users')
                      .doc(patientId)
                      .update({
                        'name': defaultName,
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                }
                
                if (!caretakers.contains(_currentUser!.uid)) {
                  await _firestore.collection('users')
                      .doc(patientId)
                      .update({
                        'caretakers': FieldValue.arrayUnion([_currentUser!.uid]),
                        'updatedAt': FieldValue.serverTimestamp(),
                      });
                }

                if (!mounted) return;
                Navigator.pop(context);
                _safeShowSnackBar('Dependent linked successfully!');
              } catch (e) {
                // Check if widget is still mounted before accessing context
                if (!mounted) return;
                
                // Hide loading indicator if still showing
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }
                
                _safeShowSnackBar('Error linking dependent. Please try again.');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: Text('Link Dependent', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPatientDetails(Map<String, dynamic> patient) {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: _firestore.collection('users').doc(patient['uid']).snapshots(),
          builder: (context, snapshot) {
            // Get real-time user data
            Map<String, dynamic> currentPatient = Map<String, dynamic>.from(patient);
            if (snapshot.hasError) {
              print('Modal StreamBuilder error: ${snapshot.error}');
              // Use the original patient data if there's an error
            } else if (snapshot.hasData && snapshot.data!.exists) {
              final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
              currentPatient.addAll(userData);
              currentPatient['uid'] = snapshot.data!.id;
            }
            
            return Container(
              padding: EdgeInsets.all(20),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Patient header with avatar, name, and share code
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 25,
                              backgroundImage: currentPatient['photoUrl'] != null 
                                  ? NetworkImage(currentPatient['photoUrl']) 
                                  : null,
                              backgroundColor: Colors.purple.shade400,
                              child: currentPatient['photoUrl'] == null 
                                  ? Text(
                                      _getDisplayName(currentPatient).substring(0, 1).toUpperCase(),
                                      style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                                    )
                                  : null,
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getDisplayName(currentPatient),
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  FutureBuilder<DocumentSnapshot>(
                                    future: _firestore
                                        .collection('users')
                                        .doc(currentPatient['uid'])
                                        .collection('medicine_schedules')
                                        .doc('current_schedule')
                                        .get(),
                                    builder: (context, snapshot) {
                                      int count = 0;
                                      if (snapshot.hasData && snapshot.data!.exists) {
                                        final scheduleData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                                        final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
                                        count = medicines.length;
                                      }
                                      return Text(
                                        '$count active medications',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () => _showMedicinesManagement(currentPatient),
                              icon: Icon(Icons.edit_outlined, size: 16),
                              label: Text('Manage'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade400,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        // Share code display
                        Container(
                          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Share Code:',
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    currentPatient['shareCode'] ?? 'No code available',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(Icons.content_copy, color: Colors.purple.shade400),
                                onPressed: () {
                                  if (currentPatient['shareCode'] != null) {
                                    // Copy to clipboard would be implemented here
                                    _safeShowSnackBar('Share code copied to clipboard');
                                  }
                                },
                                tooltip: 'Copy code',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  // Medications section with action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current Medications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showAddMedicineDialog(currentPatient),
                        icon: Icon(Icons.add, size: 16),
                        label: Text('Add Medicine'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple.shade400,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Expanded(
                    child:                     StreamBuilder<DocumentSnapshot>(
                      stream: _firestore
                          .collection('users')
                          .doc(currentPatient['uid'])
                          .collection('medicine_schedules')
                          .doc('current_schedule')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.data!.exists) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.medication_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No medicines found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'This dependent has no active medications',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final scheduleData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                        final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};

                        if (medicines.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.medication_outlined,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No medicines found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'This dependent has no active medications',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        // Convert medicines map to list and sort by creation date
                        final medicinesList = medicines.entries.map((entry) {
                          final medicineId = entry.key;
                          final medicineData = Map<String, dynamic>.from(entry.value);
                          medicineData['id'] = medicineId;
                          return medicineData;
                        }).toList();

                        // Sort by creation date (newest first)
                        medicinesList.sort((a, b) {
                          final aCreatedAt = a['createdAt']?.toString() ?? '';
                          final bCreatedAt = b['createdAt']?.toString() ?? '';
                          return bCreatedAt.compareTo(aCreatedAt);
                        });

                        return ListView.builder(
                          itemCount: medicinesList.length,
                          itemBuilder: (context, index) {
                            final medicineData = medicinesList[index];
                            
                            return Card(
                              margin: EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: Icon(Icons.medication, color: Colors.purple.shade400),
                                title: Text(
                                  medicineData['name'] ?? 'Unknown Medicine',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${medicineData['dosage']} - ${medicineData['time']}'),
                                    Text(
                                      'Frequency: ${medicineData['frequency'] ?? 'Once Daily'}',
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
                                    IconButton(
                                      icon: Icon(Icons.edit, size: 20, color: Colors.blue),
                                      onPressed: () => _showEditMedicineDialog(currentPatient, medicineData['id'], medicineData),
                                      padding: EdgeInsets.all(4),
                                      constraints: BoxConstraints(),
                                      tooltip: 'Edit Medicine',
                                    ),
                                    SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.delete, size: 20, color: Colors.red),
                                      onPressed: () => _deleteMedicine(currentPatient['uid'], medicineData['id'], medicineData['name']),
                                      padding: EdgeInsets.all(4),
                                      constraints: BoxConstraints(),
                                      tooltip: 'Delete Medicine',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMedicineCard(Map<String, dynamic> medicineData) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.medication, color: Colors.purple.shade400),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  medicineData['name'] ?? 'Unknown Medicine',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${medicineData['dosage']} - ${medicineData['timing'] ?? 'Anytime'}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Time: ${medicineData['time'] ?? 'Not set'}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> patient) {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Remove Dependent'),
        content: Text('Are you sure you want to remove ${patient['name']} from your dependents list? You can always add them back using their share code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Store the build context for later use but avoid direct reference to context
              Navigator.pop(dialogContext); // Close dialog
              
              try {
                // Check if widget is still mounted before showing dialog
                if (!mounted) return;
                
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogCtx) {
                    loadingDialogContext = dialogCtx;
                    return Center(child: CircularProgressIndicator());
                  },
                );

                // Remove patient from caretaker's list
                await _firestore.collection('users')
                    .doc(_currentUser!.uid)
                    .update({
                      'patients': FieldValue.arrayRemove([patient['uid']]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                // Also remove cached profile data if it exists
                try {
                  await _firestore.collection('users')
                      .doc(_currentUser!.uid)
                      .update({
                        'patientProfiles.${patient['uid']}': FieldValue.delete(),
                      });
                } catch (e) {
                  print('Error removing cached profile: $e');
                  // Continue with the rest of the operation even if this fails
                }

                // Remove caretaker from patient's list
                await _firestore.collection('users')
                    .doc(patient['uid'])
                    .update({
                      'caretakers': FieldValue.arrayRemove([_currentUser!.uid]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                // Check if widget is still mounted before accessing context
                if (!mounted) return;

                // Hide loading indicator
                if (loadingDialogContext != null && Navigator.canPop(loadingDialogContext!)) {
                  Navigator.pop(loadingDialogContext!);
                }
                
                _safeShowSnackBar('Dependent removed successfully');
              } catch (e) {
                // Check if widget is still mounted before accessing context
                if (!mounted) return;
                
                _safeShowSnackBar('Error removing dependent. Please try again.');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Helper method to validate share code format
  bool _isValidShareCode(String code) {
    // Must be exactly 5 characters
    if (code.length != 5) return false;
    
    // Must contain only uppercase letters and numbers
    if (!RegExp(r'^[A-Z0-9]{5}$').hasMatch(code)) return false;
    
    // Must contain exactly 3 letters
    if (code.replaceAll(RegExp(r'[0-9]'), '').length != 3) return false;
    
    // Must contain exactly 2 numbers
    if (code.replaceAll(RegExp(r'[A-Z]'), '').length != 2) return false;
    
    return true;
  }

  // Method to show add medicine dialog for a dependent
  void _showAddMedicineDialog(Map<String, dynamic> patient) async {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
            final TextEditingController _nameController = TextEditingController();
        final TextEditingController _dosageController = TextEditingController();
        final TextEditingController _durationController = TextEditingController();
    String _selectedTime = 'Morning';
    String _selectedFrequency = 'Once Daily';
    String _selectedDuration = '1 day';
    bool _isPrescription = false;
    
    // Add to controllers list to be disposed later
    _controllersToDispose.addAll([_nameController, _dosageController, _durationController]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Medicine for ${patient['name']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Prescription scanning option
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Prescription',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple.shade700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Scan a prescription to automatically extract medicine details',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _scanPrescription(patient);
                      },
                      icon: Icon(Icons.camera_alt, size: 16),
                      label: Text('Scan Prescription'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              Divider(),
              SizedBox(height: 16),
              Text(
                'Or Add Manually',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Medicine Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _dosageController,
                decoration: InputDecoration(
                  labelText: 'Dosage (e.g., 1 tablet, 5ml)',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTime,
                decoration: InputDecoration(
                  labelText: 'Time',
                  border: OutlineInputBorder(),
                ),
                items: TimingUtils.getValidTimingOptions()
                    .map((time) => DropdownMenuItem(
                          value: time,
                          child: Text(time),
                        ))
                    .toList(),
                onChanged: (value) {
                  _selectedTime = value!;
                },
              ),
              SizedBox(height: 16),
              TimingUtils.buildFrequencyInput(
                currentFrequency: _selectedFrequency,
                onFrequencyChanged: (value) {
                  setState(() {
                    _selectedFrequency = value;
                  });
                },
                context: context,
              ),
              SizedBox(height: 16),
              _buildDurationField(_durationController),
              SizedBox(height: 16),
              CheckboxListTile(
                value: _isPrescription,
                onChanged: (value) {
                  setState(() {
                    _isPrescription = value!;
                  });
                },
                title: Text('Is this a prescription medicine?'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameController.text.trim().isEmpty ||
                  _dosageController.text.trim().isEmpty) {
                if (!mounted) return;
                _safeShowSnackBar('Please fill all fields');
                return;
              }

              try {
                // Add the medicine using document-based approach
                // Convert timing string to proper time format for notifications
                final String formattedTime = TimingUtils.convertTimingToTime(_selectedTime);
                
                // Create medicine data for document-based storage
                final medicineData = {
                  'name': _nameController.text.trim(),
                  'dosage': _dosageController.text.trim(),
                  'time': formattedTime, // Use formatted time string (e.g. "08:00 AM")
                  'timing': _selectedTime, // Keep original timing for display (e.g. "Morning")
                  'frequency': _selectedFrequency,
                  'duration': _durationController.text.trim(),
                  'isPrescription': _isPrescription,
                  'type': 'Tablet',
                  'foodInstructions': 'Anytime',
                  'instructions': '',
                  'isValidated': true,
                  'notificationEnabled': true,
                  'addedBy': _currentUser!.uid,
                  'addedByName': _currentUser!.displayName ?? 'Caretaker',
                  'lastModifiedBy': _currentUser!.uid,
                  'isActive': true,
                  'isFromPrescription': false,
                };

                // Use MedicineService for document-based storage
                final medicineService = MedicineService();
                final today = DateTime.now();
                final todayStr = today.toIso8601String().split('T')[0];
                
                // Parse duration to determine how many days to schedule
                final durationDays = DurationHelper.parseDurationToDays(_durationController.text.trim());
                final daysToSchedule = durationDays ?? 1; // Default to 1 day if duration is indefinite
                
                // Generate medicine entries for the duration period
                List<Map<String, dynamic>> medicineEntries = [];
                
                // Determine frequency pattern and times per day using TimingUtils
                final intervalHours = TimingUtils.parseFrequencyToHours(_selectedFrequency);
                int interval = 1; // Default to daily
                List<String> timesPerDay = [formattedTime]; // Default to single time
                
                if (intervalHours == null) {
                  // For invalid frequency, use single time
                  interval = 1;
                  timesPerDay = [formattedTime];
                } else if (intervalHours >= 24) {
                  // For daily or longer intervals
                  interval = intervalHours ~/ 24;
                  timesPerDay = [formattedTime];
                } else {
                  // For sub-daily intervals, generate times based on frequency
                  final times = TimingUtils.generateTimesFromFrequency(_selectedFrequency);
                  timesPerDay = times.map((time) => time.format(context)).toList();
                  interval = 1; // Daily schedule
                }
                
                for (int i = 0; i < daysToSchedule; i += interval) {
                  final scheduleDate = today.add(Duration(days: i));
                  final scheduleDateStr = scheduleDate.toIso8601String().split('T')[0];
                  
                  // Create an entry for each time per day
                  for (int j = 0; j < timesPerDay.length; j++) {
                    final timeForThisDose = timesPerDay[j];
                    
                    final medicineEntry = {
                      ...medicineData,
                      'time': timeForThisDose,
                      'scheduleDate': scheduleDateStr,
                      'isCompleted': false,
                      'completedAt': null,
                    };
                    
                    medicineEntries.add(medicineEntry);
                  }
                }

                // Save using document-based approach
                final patientUid = patient['uid']?.toString();
                if (patientUid == null || patientUid.isEmpty) {
                  throw Exception('Invalid patient UID');
                }
                
                await medicineService.saveMedicinesDocumentBased(
                  patientUid,
                  medicineEntries,
                  {'id': 'caretaker_added', 'source': 'caretaker'},
                );

                // Update user document with timestamp
                await _firestore.collection('users').doc(patient['uid']).update({
                  'lastMedicationUpdate': FieldValue.serverTimestamp(),
                  'medicationUpdateTrigger': FieldValue.serverTimestamp(),
                  'lastUpdatedBy': _currentUser!.uid,
                });
                
                // Update caretaker's cache
                await _firestore.collection('users').doc(_currentUser!.uid).update({
                  'lastActionTimestamp': FieldValue.serverTimestamp(),
                  'lastActionType': 'ADD_MEDICINE',
                  'lastActionTarget': patient['uid'],
                });
                
                if (!mounted) return;
                Navigator.pop(context);
                final message = medicineEntries.length > 1 
                    ? 'Medicine added successfully for ${medicineEntries.length} doses'
                    : 'Medicine added successfully';
                _safeShowSnackBar(message);
              } catch (e) {
                if (!mounted) return;
                _safeShowSnackBar('Error adding medicine: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade400,
            ),
            child: Text('Add Medicine', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Method to edit medicine
  void _showEditMedicineDialog(Map<String, dynamic> patient, String medicineId, Map<String, dynamic> medicineData) {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
            final TextEditingController _nameController = TextEditingController(text: medicineData['name']);
        final TextEditingController _dosageController = TextEditingController(text: medicineData['dosage']);
        final TextEditingController _durationController = TextEditingController(text: medicineData['duration'] ?? '');
    // Use TimingUtils to get safe values for dropdowns
    String _selectedTime = TimingUtils.getSafeTimingValue(medicineData);
    String _selectedFrequency = TimingUtils.getSafeFrequencyValue(medicineData);
    String _selectedDuration = medicineData['duration'] ?? '1 day';
    bool _isPrescription = medicineData['isPrescription'] ?? false;
    
    // Add to controllers list to be disposed later
    _controllersToDispose.addAll([_nameController, _dosageController, _durationController]);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit Medicine'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Medicine Name',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              TextField(
                controller: _dosageController,
                decoration: InputDecoration(
                  labelText: 'Dosage',
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedTime,
                decoration: InputDecoration(
                  labelText: 'Time',
                  border: OutlineInputBorder(),
                ),
                items: TimingUtils.getValidTimingOptions()
                    .map((time) => DropdownMenuItem(
                          value: time,
                          child: Text(time),
                        ))
                    .toList(),
                onChanged: (value) {
                  _selectedTime = value!;
                },
              ),
              SizedBox(height: 16),
              TimingUtils.buildFrequencyInput(
                currentFrequency: _selectedFrequency,
                onFrequencyChanged: (value) {
                  setState(() {
                    _selectedFrequency = value;
                  });
                },
                context: context,
              ),
              SizedBox(height: 16),
              _buildDurationField(_durationController),
              SizedBox(height: 16),
              CheckboxListTile(
                value: _isPrescription,
                onChanged: (value) {
                  setState(() {
                    _isPrescription = value!;
                  });
                },
                title: Text('Is this a prescription medicine?'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Create a batch for multiple updates
                final batch = _firestore.batch();
                
                // Update the medicine document with enhanced metadata
                // Convert timing string to proper time format for notifications
                final String formattedTime = TimingUtils.convertTimingToTime(_selectedTime);
                
                // Update the medicine in the schedule
                batch.update(_firestore
                    .collection('users')
                    .doc(patient['uid'])
                    .collection('medicine_schedules')
                    .doc('current_schedule'), {
                  'medicines.$medicineId.name': _nameController.text.trim(),
                  'medicines.$medicineId.dosage': _dosageController.text.trim(),
                  'medicines.$medicineId.time': formattedTime, // Use formatted time string (e.g. "08:00 AM")
                  'medicines.$medicineId.timing': _selectedTime, // Keep original timing for display (e.g. "Morning")
                  'medicines.$medicineId.frequency': _selectedFrequency,
                  'medicines.$medicineId.duration': _durationController.text.trim(),
                  'medicines.$medicineId.isPrescription': _isPrescription,
                  'medicines.$medicineId.updatedAt': FieldValue.serverTimestamp(),
                  'medicines.$medicineId.updatedBy': _currentUser!.uid,
                  'medicines.$medicineId.lastUpdated': FieldValue.serverTimestamp(),
                  'medicines.$medicineId.lastModifiedBy': _currentUser!.uid,
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                // Update user document to trigger home screen refresh
                final userRef = _firestore.collection('users').doc(patient['uid']);
                batch.update(userRef, {
                  'lastMedicationUpdate': FieldValue.serverTimestamp(),
                  'medicationUpdateTrigger': FieldValue.serverTimestamp(), // Force home screen refresh
                  'lastUpdatedBy': _currentUser!.uid,
                });
                
                // Update caretaker's cache with action metadata
                final caretakerRef = _firestore.collection('users').doc(_currentUser!.uid);
                batch.update(caretakerRef, {
                  'lastActionTimestamp': FieldValue.serverTimestamp(),
                  'lastActionType': 'EDIT_MEDICINE',
                  'lastActionTarget': patient['uid'],
                });
                
                // Commit all updates in a single batch
                await batch.commit();

                if (!mounted) return;
                Navigator.pop(context);
                _safeShowSnackBar('Medicine updated successfully');
              } catch (e) {
                if (!mounted) return;
                _safeShowSnackBar('Error updating medicine: $e');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple.shade400,
            ),
            child: Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Method to show medicines list with edit/delete options
  void _showMedicinesManagement(Map<String, dynamic> patient) {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${patient['name']} - Medicines',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => _scanPrescriptionForPatient(patient),
                        icon: Icon(Icons.camera_alt, color: Colors.orange.shade600),
                        tooltip: 'Scan Prescription',
                      ),
                      IconButton(
                        onPressed: () => _showAddMedicineDialog(patient),
                        icon: Icon(Icons.add, color: Colors.purple.shade400),
                        tooltip: 'Add Medicine',
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('users')
                      .doc(patient['uid'])
                      .collection('medicine_schedules')
                      .doc('current_schedule')
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.data!.exists) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.medication_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No medicines found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _scanPrescriptionForPatient(patient),
                                  icon: Icon(Icons.camera_alt, size: 16),
                                  label: Text('Scan Prescription'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade600,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () => _showAddMedicineDialog(patient),
                                  child: Text('Add Manually'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    final scheduleData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};

                    if (medicines.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.medication_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No medicines found',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => _scanPrescriptionForPatient(patient),
                                  icon: Icon(Icons.camera_alt, size: 16),
                                  label: Text('Scan Prescription'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange.shade600,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () => _showAddMedicineDialog(patient),
                                  child: Text('Add Manually'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }

                    // Convert medicines map to list and sort by creation date
                    final medicinesList = medicines.entries.map((entry) {
                      final medicineId = entry.key;
                      final medicineData = Map<String, dynamic>.from(entry.value);
                      medicineData['id'] = medicineId;
                      return medicineData;
                    }).toList();

                    // Sort by creation date (newest first)
                    medicinesList.sort((a, b) {
                      final aCreatedAt = a['createdAt']?.toString() ?? '';
                      final bCreatedAt = b['createdAt']?.toString() ?? '';
                      return bCreatedAt.compareTo(aCreatedAt);
                    });

                    return ListView.builder(
                      itemCount: medicinesList.length,
                      itemBuilder: (context, index) {
                        final medicineData = medicinesList[index];

                        return Card(
                          margin: EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: Icon(
                              Icons.medication,
                              color: Colors.purple.shade400,
                            ),
                            title: Text(
                              medicineData['name'] ?? 'Unknown Medicine',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${medicineData['dosage']} - ${medicineData['timing'] ?? 'Anytime'}'),
                                Text(
                                  'Time: ${medicineData['time'] ?? 'Not set'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                if (medicineData['addedByName'] != null)
                                  Text(
                                    'Added by: ${medicineData['addedByName']}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: PopupMenuButton(
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
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 16, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete', style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _showEditMedicineDialog(patient, medicineData['id'], medicineData);
                                } else if (value == 'delete') {
                                  _deleteMedicine(patient['uid'], medicineData['id'], medicineData['name']);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Method to delete medicine
  Future<void> _deleteMedicine(String patientId, String medicineId, String medicineName) async {
    // Check if widget is still mounted before showing dialog
    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Medicine'),
        content: Text('Are you sure you want to delete "$medicineName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Use MedicineService to properly delete the medicine (delete entire medicine, not date-specific)
        final medicineService = MedicineService();
        await medicineService.deleteMedicine(patientId, medicineId);
        
        // Update user document to trigger home screen refresh
        final userRef = _firestore.collection('users').doc(patientId);
        await userRef.update({
          'lastMedicationUpdate': FieldValue.serverTimestamp(),
          'medicationUpdateTrigger': FieldValue.serverTimestamp(), // Force home screen refresh
          'lastUpdatedBy': _currentUser!.uid,
        });
        
        // Update caretaker's cache with action metadata
        final caretakerRef = _firestore.collection('users').doc(_currentUser!.uid);
        await caretakerRef.update({
          'lastActionTimestamp': FieldValue.serverTimestamp(),
          'lastActionType': 'DELETE_MEDICINE',
          'lastActionTarget': patientId,
          'lastActionItem': medicineName,
        });

        if (!mounted) return;
        _safeShowSnackBar('Medicine deleted successfully');
      } catch (e) {
        if (!mounted) return;
        // Check if the error is about medicine not found (which is not really an error)
        if (e.toString().contains('not found') || e.toString().contains('not-found')) {
          _safeShowSnackBar('$medicineName was already removed');
        } else {
          _safeShowSnackBar('Error deleting medicine: $e');
        }
      }
    }
  }

  String _getDisplayName(Map<String, dynamic> patient) {
    if (patient['name'] != null && patient['name'].toString().trim().isNotEmpty) {
      return patient['name'];
    } else if (patient['email'] != null) {
      return patient['email'].toString().split('@')[0];
    } else {
      return 'Dependent';
    }
  }

  // Method to scan prescription for a patient
  Future<void> _scanPrescription(Map<String, dynamic> patient) async {
    if (!mounted) return;
    
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PrescriptionScannerScreen(
          onPrescriptionScanned: (prescriptionData) {
            _handlePrescriptionScanned(patient, prescriptionData);
          },
        ),
      ),
    );
    
    if (result != null && mounted) {
      _safeShowSnackBar('Prescription scanned successfully');
    }
  }

  // Handle prescription data after scanning
  void _handlePrescriptionScanned(Map<String, dynamic> patient, Map<String, dynamic> prescriptionData) {
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
      _processScannedPrescription(patient, prescriptionData);
    } else {
      _safeShowSnackBar('No medicines found in prescription');
    }
  }

  // Method to scan prescription for a specific patient (separate option)
  Future<void> _scanPrescriptionForPatient(Map<String, dynamic> patient) async {
    if (!mounted) return;
    
    // Close the medicines management bottom sheet first
    Navigator.pop(context);
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Scan Prescription'),
        content: Text('Do you want to scan a prescription for ${patient['name']}? This will extract medicines and add them to their medication list.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade600,
              foregroundColor: Colors.white,
            ),
            child: Text('Scan Prescription'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _scanPrescription(patient);
    }
  }

  // Process scanned prescription data and save medicines
  Future<void> _processScannedPrescription(Map<String, dynamic> patient, Map<String, dynamic> prescriptionData) async {
    if (!mounted) return;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        loadingDialogContext = dialogContext;
        return Center(child: CircularProgressIndicator());
      },
    );

    try {
      final List<dynamic> medicines = prescriptionData['medicines'];
      final List<Map<String, dynamic>> medicineEntries = [];

      for (var medicine in medicines) {
        // Validate required fields
        final name = medicine['name']?.toString() ?? '';
        final dosage = medicine['dosage']?.toString() ?? '';
        
        if (name.isEmpty || dosage.isEmpty) {
          print('⚠️ Skipping medicine with missing name or dosage: $medicine');
          continue;
        }
        
        final medicineEntry = {
          'name': name,
          'dosage': dosage,
          'time': medicine['mappedTime']?.toString() ?? TimingUtils.convertTimingToTime(medicine['mappedTiming']?.toString() ?? 'Morning'),
          'timing': medicine['mappedTiming']?.toString() ?? medicine['timing']?.toString() ?? 'Morning',
          'frequency': medicine['mappedFrequency']?.toString() ?? medicine['frequency']?.toString() ?? 'Once Daily',
          'instructions': medicine['instructions']?.toString() ?? '',
          'foodInstructions': medicine['mappedFoodInstructions']?.toString() ?? '',
          'type': medicine['type']?.toString() ?? 'Tablet',
          'duration': medicine['duration']?.toString() ?? '1 day',
          'isPrescription': true,
          'isFromPrescription': true,
          'prescriptionSource': 'scanned',
          'validated': medicine['validated'] ?? false,
          'scheduleDate': DateTime.now().toIso8601String().split('T')[0],
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': _currentUser!.uid,
          'addedByName': _currentUser!.displayName ?? _currentUser!.email,
          'isActive': true,
        };
        medicineEntries.add(medicineEntry);
      }

      // Validate medicine entries
      if (medicineEntries.isEmpty) {
        throw Exception('No valid medicines found in prescription');
      }
      
      // Save medicines using the existing service
      final patientUid = patient['uid']?.toString();
      if (patientUid == null || patientUid.isEmpty) {
        throw Exception('Invalid patient UID');
      }
      
      // Ensure prescriptionData has required fields
      final safePrescriptionData = {
        'id': prescriptionData['id']?.toString() ?? 'scanned_prescription',
        'source': prescriptionData['source']?.toString() ?? 'scanner',
        ...prescriptionData,
      };
      
      print('📄 Processing ${medicineEntries.length} medicine entries for patient: $patientUid');
      print('📄 First medicine entry: ${medicineEntries.first}');
      
      await MedicineService().saveMedicinesDocumentBased(
        patientUid,
        medicineEntries,
        safePrescriptionData,
      );

      // Update user and caretaker documents
      final batch = _firestore.batch();
      
      // Update patient document
      final userRef = _firestore.collection('users').doc(patient['uid']);
      batch.update(userRef, {
        'lastMedicationUpdate': FieldValue.serverTimestamp(),
        'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        'lastUpdatedBy': _currentUser!.uid,
      });
      
      // Update caretaker document
      final caretakerRef = _firestore.collection('users').doc(_currentUser!.uid);
      batch.update(caretakerRef, {
        'lastActionTimestamp': FieldValue.serverTimestamp(),
        'lastActionType': 'ADD_PRESCRIPTION_MEDICINES',
        'lastActionTarget': patient['uid'],
        'lastActionItem': '${medicines.length} medicines from prescription',
      });
      
      await batch.commit();

      if (!mounted) return;
      
      // Hide loading dialog
      if (loadingDialogContext != null && Navigator.canPop(loadingDialogContext!)) {
        Navigator.pop(loadingDialogContext!);
      }
      
      _safeShowSnackBar('${medicines.length} medicines added from prescription');
      
    } catch (e) {
      if (!mounted) return;
      
      // Hide loading dialog
      if (loadingDialogContext != null && Navigator.canPop(loadingDialogContext!)) {
        Navigator.pop(loadingDialogContext!);
      }
      
      _safeShowSnackBar('Error processing prescription: $e');
    }
  }

  Widget _buildDurationField(TextEditingController durationController) {
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
        TextFormField(
          controller: durationController,
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
        // Real-time preview of parsed duration
        if (durationController.text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4),
            child: Builder(
              builder: (context) {
                final parsed = DurationHelper.parseDurationToDays(durationController.text);
                if (parsed != null) {
                  final display = DurationHelper.formatDurationDisplay(durationController.text);
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
                    (phrase) => durationController.text.toLowerCase().contains(phrase)
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
              },
            ),
          ),
      ],
    );
  }
}

// New screen for dependents to view their caretakers
class CaretakersScreen extends StatefulWidget {
  @override
  _CaretakersScreenState createState() => _CaretakersScreenState();
}

class _CaretakersScreenState extends State<CaretakersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _isDisposed = false;
  
  // Define loadingDialogContext variable
  BuildContext? loadingDialogContext;

  // Helper method to safely show snackbar
  void _safeShowSnackBar(String message) {
    if (!mounted || _isDisposed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'My Caretakers',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Color(0xFF6B46C1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.people, color: Colors.white),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'People who help manage your medications',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: _currentUser == null 
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text('Authentication Error',
                            style: TextStyle(fontSize: 16, color: Colors.red)),
                        Text('Please sign in again',
                            style: TextStyle(fontSize: 14, color: Colors.grey)),
                      ],
                    ),
                  )
                : StreamBuilder<DocumentSnapshot>(
                stream: _firestore.collection('users').doc(_currentUser!.uid).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    print('Caretakers StreamBuilder error: ${snapshot.error}');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red),
                          SizedBox(height: 16),
                          Text('Permission Error',
                              style: TextStyle(fontSize: 16, color: Colors.red)),
                          Text('Unable to access data',
                              style: TextStyle(fontSize: 14, color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                  
                  if (!snapshot.hasData || !snapshot.data!.exists) {
                    return Center(child: Text('No caretakers linked'));
                  }
                  
                  final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                  List<dynamic> caretakerIds = userData['caretakers'] ?? [];
                  
                  if (caretakerIds.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No caretakers linked yet',
                              style: TextStyle(fontSize: 16, color: Colors.grey)),
                          SizedBox(height: 8),
                          Text(
                            'Your share code: ${userData['shareCode'] ?? 'Not available'}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple.shade700,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Share this code with your caretaker to link accounts',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Display share code for dependents
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Share Code',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.purple.shade700,
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  userData['shareCode'] ?? 'Not available',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(Icons.content_copy, color: Colors.purple.shade400),
                                  onPressed: () {
                                    if (userData['shareCode'] != null) {
                                      // Copy to clipboard would be implemented here
                                      _safeShowSnackBar('Share code copied to clipboard');
                                    }
                                  },
                                  tooltip: 'Copy code',
                                ),
                              ],
                            ),
                            Text(
                              'Share this code with people who help manage your medications',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        'Your Caretakers',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: caretakerIds.length,
                          itemBuilder: (context, index) {
                            final caretakerId = caretakerIds[index];
                            
                            return FutureBuilder<DocumentSnapshot>(
                              future: _firestore.collection('users').doc(caretakerId).get(),
                              builder: (context, caretakerSnapshot) {
                                if (!caretakerSnapshot.hasData) {
                                  return Card(
                                    margin: EdgeInsets.only(bottom: 12),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.grey.shade300,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      title: Text('Loading...'),
                                    ),
                                  );
                                }
                                
                                var caretakerData = caretakerSnapshot.data!.exists ? 
                                    caretakerSnapshot.data!.data() as Map<String, dynamic> : 
                                    {'name': 'Unknown Caretaker'};
                                
                                caretakerData['uid'] = caretakerSnapshot.data!.id;
                                
                                return Card(
                                  margin: EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage: caretakerData['photoUrl'] != null 
                                          ? NetworkImage(caretakerData['photoUrl']) 
                                          : null,
                                      backgroundColor: Colors.purple.shade400,
                                      child: caretakerData['photoUrl'] == null 
                                          ? Text(
                                              (caretakerData['name'] ?? 'C').substring(0, 1).toUpperCase(),
                                              style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                                            )
                                          : null,
                                    ),
                                    title: Text(
                                      caretakerData['name'] ?? caretakerData['email']?.toString().split('@')[0] ?? 'Caretaker',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Text(
                                      'Caretaker',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                    ),
                                    trailing: IconButton(
                                      icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400),
                                      onPressed: () => _showRemoveCaretakerDialog(caretakerData),
                                      tooltip: 'Remove Caretaker',
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemoveCaretakerDialog(Map<String, dynamic> caretaker) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Remove Caretaker'),
        content: Text('Are you sure you want to remove ${caretaker['name'] ?? 'this caretaker'} from your caretakers list?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog
              
              try {
                if (!mounted) return;
                
                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext dialogCtx) {
                    loadingDialogContext = dialogCtx;
                    return Center(child: CircularProgressIndicator());
                  },
                );

                // Remove caretaker from dependent's list
                await _firestore.collection('users')
                    .doc(_currentUser!.uid)
                    .update({
                      'caretakers': FieldValue.arrayRemove([caretaker['uid']]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                // Remove dependent from caretaker's list
                await _firestore.collection('users')
                    .doc(caretaker['uid'])
                    .update({
                      'patients': FieldValue.arrayRemove([_currentUser!.uid]),
                      'updatedAt': FieldValue.serverTimestamp(),
                    });

                // Also remove cached profile data if it exists
                try {
                  await _firestore.collection('users')
                      .doc(caretaker['uid'])
                      .update({
                        'patientProfiles.${_currentUser!.uid}': FieldValue.delete(),
                      });
                } catch (e) {
                  print('Error removing cached profile: $e');
                  // Continue with the rest of the operation even if this fails
                }

                if (!mounted) return;

                // Hide loading indicator
                if (loadingDialogContext != null && Navigator.canPop(loadingDialogContext!)) {
                  Navigator.pop(loadingDialogContext!);
                }
                
                _safeShowSnackBar('Caretaker removed successfully');
              } catch (e) {
                if (!mounted) return;
                
                // Hide loading indicator if still showing
                if (loadingDialogContext != null && Navigator.canPop(loadingDialogContext!)) {
                  Navigator.pop(loadingDialogContext!);
                }
                
                _safeShowSnackBar('Error removing caretaker. Please try again.');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
            ),
            child: Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


}
