import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class UserDetails {
  final String id;
  final String name;
  final String email;
  final String photoUrl;

  UserDetails({
    required this.id,
    required this.name,
    required this.email,
    required this.photoUrl,
  });

  factory UserDetails.fromFirebaseUser(User user) {
    return UserDetails(
      id: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      photoUrl: user.photoURL ?? '',
    );
  }
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  User? _user;
  UserDetails? _userDetails;
  bool _isLoading = false;

  User? get user => _user;
  UserDetails? get userDetails => _userDetails;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _user != null;

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      _userDetails = user != null ? UserDetails.fromFirebaseUser(user) : null;
      notifyListeners();
    });
  }

  Future<void> handleError(dynamic e) async {
    print('Auth error: $e');
    await signOut();
    throw e;
  }

  Future<UserDetails?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Sign in with Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      try {
        // Get auth details
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        
        // Create credential
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        // Sign in to Firebase
        final userCredential = await _auth.signInWithCredential(credential);
        
        // Get user data directly from userCredential
        if (userCredential.user == null) {
          throw Exception('Failed to get user data');
        }

        // Create user details manually
        _userDetails = UserDetails(
          id: userCredential.user!.uid,
          name: userCredential.user!.displayName ?? '',
          email: userCredential.user!.email ?? '',
          photoUrl: userCredential.user!.photoURL ?? '',
        );

        // Migrate local data if user was using the app without authentication
        await _migrateLocalDataToAuthenticatedUser();

        await _saveLoginState(true);
        notifyListeners();
        return _userDetails;

      } catch (e) {
        print('Firebase credential error: $e');
        await _googleSignIn.signOut();
        await _auth.signOut();
        return null;
      }

    } catch (e) {
      print('Google sign in error: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      final result = await _auth.signInWithEmailAndPassword(email: email, password: password);
      _userDetails = result.user != null ? UserDetails.fromFirebaseUser(result.user!) : null;
      
      // Migrate local data if user was using the app without authentication
      if (_userDetails != null) {
        await _migrateLocalDataToAuthenticatedUser();
      }
      
      await _saveLoginState(true); // Save login state
      return result;
    } catch (e) {
      await handleError(e);
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<UserCredential?> signUpWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      final result = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      await _saveLoginState(true);
      return result;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
    await _saveLoginState(false); // Clear login state
    
    // Clear local user data to ensure proper isolation
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('name');
    await prefs.remove('user_id');
    
    // Clear per-user name setup data for the current user
    if (_userDetails != null) {
      final userId = _userDetails!.id;
      await prefs.remove('name_$userId');
      await prefs.remove('name_setup_completed_$userId');
      print('Cleared name setup data for user $userId');
    }
    
    print('Cleared local user data on sign out');
  }

  Future<void> _saveLoginState(bool isLoggedIn) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', isLoggedIn);
    
    // Also save user ID if user is logged in
    if (isLoggedIn && _userDetails != null) {
      await prefs.setString('user_id', _userDetails!.id);
    } else if (!isLoggedIn) {
      // Clear user ID when logging out
      await prefs.remove('user_id');
    }
  }

  Future<bool> checkLoginState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getBool('isLoggedIn') ?? false;
  }

  Future<bool> isUserLoggedIn() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();
    final hasSeenFeatures = prefs.getBool('has_seen_features') ?? false;
    
    if (currentUser != null) {
      // Set features as seen for logged in users
      await prefs.setBool('has_seen_features', true);
      return true;
    }
    return false;
  }

  // Add this method to allow updating the user's name
  Future<void> updateUserName(String name) async {
    if (_userDetails != null) {
      // Update in memory
      _userDetails = UserDetails(
        id: _userDetails!.id,
        name: name,
        email: _userDetails!.email,
        photoUrl: _userDetails!.photoUrl,
      );
      
      // Save to Firestore
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userDetails!.id)
            .set({
              'name': name,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
        print('Name updated in Firestore: $name');
      } catch (e) {
        print('Error updating name in Firestore: $e');
      }
      
      notifyListeners();
    }
  }

  // Migrate local data to authenticated user
  Future<void> _migrateLocalDataToAuthenticatedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localUserId = prefs.getString('user_id');
      final localName = prefs.getString('name');
      
      // Only migrate if there's local data and it's different from the authenticated user
      if (localUserId != null && localUserId.isNotEmpty && 
          localUserId != _userDetails!.id && localName != null && localName.isNotEmpty) {
        
        print('Migrating local data from $localUserId to ${_userDetails!.id}');
        
        // Update the name if the authenticated user doesn't have one
        if (_userDetails!.name.isEmpty && localName.isNotEmpty) {
          await updateUserName(localName);
        }
        
        // Clear the local user ID to prevent future conflicts
        await prefs.remove('user_id');
        print('Migration completed');
      }
    } catch (e) {
      print('Error during data migration: $e');
    }
  }

  // Check if user needs to complete name setup
  Future<bool> needsNameSetup() async {
    try {
      if (!isAuthenticated || _userDetails == null) return false;
      
      final prefs = await SharedPreferences.getInstance();
      final userId = _userDetails!.id;
      final savedName = prefs.getString('name_$userId');
      
      // If we have a name in SharedPreferences, user doesn't need setup
      if (savedName != null && savedName.isNotEmpty) {
        return false;
      }
      
      // If no name in SharedPreferences, check Firebase
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        
        if (doc.exists && doc.data()?['name'] != null) {
          final firebaseName = doc.data()!['name'] as String;
          if (firebaseName.isNotEmpty) {
            // Save to SharedPreferences for future use
            await prefs.setString('name_$userId', firebaseName);
            print('Loaded name from Firebase during needsNameSetup check: $firebaseName');
            return false; // User has a name in Firebase, no setup needed
          }
        }
      } catch (e) {
        print('Error checking Firebase for name during needsNameSetup: $e');
      }
      
      // If no name found in either SharedPreferences or Firebase, user needs setup
      return true;
    } catch (e) {
      print('Error checking name setup status: $e');
      return true; // Default to showing name dialog if there's an error
    }
  }

  // Add this method to generate share codes
  Future<String> generateShareCode() async {
    final user = this.user;
    if (user == null) throw Exception('No user logged in');
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // Check if share code already exists
      final doc = await docRef.get();
      if (doc.exists && doc.data()?['shareCode'] != null) {
        String existingCode = doc.data()!['shareCode'] as String;
        // Validate existing code format
        if (_isValidShareCode(existingCode)) {
          return existingCode;
        }
        // If existing code doesn't meet requirements, generate a new one
      }

      // Generate new code only if one doesn't exist or is invalid
      final code = _generateRandomCode();
      await docRef.set({
        'shareCode': code,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return code;
    } catch (e) {
      print('Error generating/retrieving share code: $e');
      throw e;
    }
  }

  // Private helper to validate share code format
  bool _isValidShareCode(String code) {
    // Must be exactly 5 characters
    if (code.length != 5) return false;
    
    // Must contain only uppercase letters and numbers
    if (!RegExp(r'^[A-Z0-9]{5}$').hasMatch(code)) return false;
    
    // Must contain at least one letter
    if (!code.contains(RegExp(r'[A-Z]'))) return false;
    
    // Must contain at least one number
    if (!code.contains(RegExp(r'[0-9]'))) return false;
    
    return true;
  }

  // Private helper to generate a random alphanumeric code
  String _generateRandomCode() {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const numbers = '0123456789';
    final rand = Random.secure();
    
    // Always include exactly 3 letters and 2 numbers
    List<String> code = [];
    
    // Add 3 random letters
    for (int i = 0; i < 3; i++) {
      code.add(letters[rand.nextInt(letters.length)]);
    }
    
    // Add 2 random numbers
    for (int i = 0; i < 2; i++) {
      code.add(numbers[rand.nextInt(numbers.length)]);
    }
    
    // Shuffle the code to randomize position of letters and numbers
    code.shuffle(rand);
    
    return code.join();
  }
}
