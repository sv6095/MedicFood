import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medicine.dart';
import '../utils/duration_helper.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MedicineService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Check if user is authenticated
  bool _isUserAuthenticated() {
    final user = FirebaseAuth.instance.currentUser;
    return user != null;
  }
  
  // Get current user ID with validation
  String? _getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    return user?.uid;
  }
  
  // Constants for optimization
  static const int BATCH_SIZE_LIMIT = 500; // Firestore batch limit
  static const int CHUNK_SIZE = 400; // Safe chunk size for processing
  static const int LARGE_DATASET_THRESHOLD = 100; // Threshold for large dataset optimization

  Future<void> saveMedicine(String userId, Map<String, dynamic> medicineData) async {
    try {
      // Ensure the medicine data includes a scheduleDate field
      if (!medicineData.containsKey('scheduleDate')) {
        medicineData['scheduleDate'] = DateTime.now().toIso8601String().split('T')[0];
      }
      
      // Add creation timestamp
      medicineData['createdAt'] = DateTime.now().toIso8601String();
      
      // Generate a unique medicine ID
      final medicineId = _firestore.collection('users').doc().id;
      medicineData['id'] = medicineId;
      
      // Get the current schedule document
      final scheduleDocRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule');
      
      // Get existing schedule data or create new
      final scheduleDoc = await scheduleDocRef.get();
      Map<String, dynamic> scheduleData;
      
      if (scheduleDoc.exists) {
        scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      } else {
        scheduleData = {
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'medicines': {},
        };
      }
      
      // Prepare the medicine schedule data
      final scheduleDate = medicineData['scheduleDate'] as String;
      final scheduleDataEntry = {
        'date': scheduleDate,
        'isCompleted': false,
        'completedAt': null,
        'notes': medicineData['notes'] ?? '',
      };
      
      // Create or update the medicine in the schedule
      final medicines = Map<String, dynamic>.from(scheduleData['medicines'] ?? {});
      final existingMedicine = medicines[medicineId] as Map<String, dynamic>?;
      
      if (existingMedicine != null) {
        // Update existing medicine
        final scheduleDataList = List<Map<String, dynamic>>.from(existingMedicine['scheduleData'] ?? []);
        
        // Check if this date already exists in the schedule
        final existingIndex = scheduleDataList.indexWhere((entry) => entry['date'] == scheduleDate);
        if (existingIndex >= 0) {
          // Update existing entry
          scheduleDataList[existingIndex] = scheduleDataEntry;
        } else {
          // Add new entry
          scheduleDataList.add(scheduleDataEntry);
        }
        
        medicines[medicineId] = {
          ...existingMedicine,
          'scheduleData': scheduleDataList,
          'updatedAt': FieldValue.serverTimestamp(),
        };
      } else {
        // Create new medicine
        medicines[medicineId] = {
          ...medicineData,
          'scheduleData': [scheduleDataEntry],
          'scheduleDates': [scheduleDate],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
      }
      
      // Update the schedule document
      await scheduleDocRef.set({
        ...scheduleData,
        'medicines': medicines,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
    } catch (e) {
      throw Exception('Failed to save medicine: $e');
    }
  }

  /// Optimized method for saving large prescription datasets
  /// Uses chunked processing and background operations for better performance
  Future<void> savePrescriptionMedicinesOptimized(
    String userId, 
    List<Map<String, dynamic>> medicines, 
    Map<String, dynamic> prescriptionData,
    {Function(int current, int total)? onProgress}
  ) async {
    try {
      print('🚀 Starting optimized save for ${medicines.length} medicine entries...');
      
      // Check if this is a large dataset that needs optimization
      if (medicines.length > LARGE_DATASET_THRESHOLD) {
        print('📊 Large dataset detected (${medicines.length} entries), using chunked processing...');
        await _saveLargeDatasetChunked(userId, medicines, prescriptionData, onProgress);
      } else {
        print('📊 Small dataset (${medicines.length} entries), using standard batch processing...');
        await _saveStandardBatch(userId, medicines, prescriptionData);
      }
      
      // Update the trigger field to refresh StreamBuilder
      await _firestore.collection('users').doc(userId).update({
        'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        'lastPrescriptionSaved': FieldValue.serverTimestamp(),
      });
      
      print('✅ Successfully saved all medicines to Firestore');
      
    } catch (e) {
      print('❌ Error saving prescription medicines: $e');
      throw Exception('Failed to save prescription medicines: $e');
    }
  }

  /// Process large datasets in chunks to avoid timeout and memory issues
  Future<void> _saveLargeDatasetChunked(
    String userId, 
    List<Map<String, dynamic>> medicines, 
    Map<String, dynamic> prescriptionData,
    Function(int current, int total)? onProgress
  ) async {
    final totalEntries = medicines.length;
    int processedEntries = 0;
    
    // Process in chunks
    for (int i = 0; i < medicines.length; i += CHUNK_SIZE) {
      final endIndex = (i + CHUNK_SIZE < medicines.length) ? i + CHUNK_SIZE : medicines.length;
      final chunk = medicines.sublist(i, endIndex);
      
      print('📦 Processing chunk ${(i ~/ CHUNK_SIZE) + 1}/${(medicines.length / CHUNK_SIZE).ceil()} (${chunk.length} entries)');
      
      // Save this chunk
      await _saveStandardBatch(userId, chunk, prescriptionData);
      
      processedEntries += chunk.length;
      onProgress?.call(processedEntries, totalEntries);
      
      // Small delay to prevent overwhelming the database
      if (endIndex < medicines.length) {
        await Future.delayed(Duration(milliseconds: 100));
      }
    }
  }

  /// Standard batch processing for smaller datasets
  Future<void> _saveStandardBatch(
    String userId, 
    List<Map<String, dynamic>> medicines, 
    Map<String, dynamic> prescriptionData
  ) async {
    // Get the current schedule document
    final scheduleDocRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('medicine_schedules')
        .doc('current_schedule');
    
    // Get existing schedule data or create new
    final scheduleDoc = await scheduleDocRef.get();
    Map<String, dynamic> scheduleData;
    
    if (scheduleDoc.exists) {
      scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
    } else {
      scheduleData = {
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'medicines': {},
      };
    }
    
    // Get existing medicines map to preserve existing medicines
    final existingMedicines = Map<String, dynamic>.from(scheduleData['medicines'] ?? {});
    
    // Process each medicine
    for (var medicine in medicines) {
      final medicineId = _firestore.collection('users').doc().id;
      
      // Prepare the medicine data
      final medicineDataWithPrescription = {
        ...medicine,
        'id': medicineId,
        'prescriptionId': prescriptionData['id']?.toString() ?? 'manual_entry',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'isFromPrescription': true,
        'isActive': true,
      };
      
      // Prepare schedule data for this medicine
      final scheduleDate = medicine['scheduleDate'] as String? ?? DateTime.now().toIso8601String().split('T')[0];
      final scheduleDataEntry = {
        'date': scheduleDate,
        'isCompleted': false,
        'completedAt': null,
        'notes': medicine['notes'] ?? '',
      };
      
      // Add to existing medicines map (preserving existing medicines)
      existingMedicines[medicineId] = {
        ...medicineDataWithPrescription,
        'scheduleData': [scheduleDataEntry],
        'scheduleDates': [scheduleDate],
      };
    }
    
    // Update the schedule document with merged medicines
    await scheduleDocRef.set({
      ...scheduleData,
      'medicines': existingMedicines,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Alternative approach: Save recurring medicine pattern instead of individual entries
  /// This is more efficient for long-term prescriptions
  Future<void> saveRecurringMedicinePattern(
    String userId,
    Map<String, dynamic> medicinePattern,
    Map<String, dynamic> prescriptionData,
    {int? maxDays}
  ) async {
    try {
      print('🔄 Saving recurring medicine pattern for ${medicinePattern['name']?.toString() ?? 'Unknown Medicine'}');
      
      // Create a pattern document that defines the recurring medicine
      final patternRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_patterns')
          .doc();
      
      final patternData = {
        ...medicinePattern,
        'id': patternRef.id,
        'prescriptionId': prescriptionData['id']?.toString() ?? 'manual_entry',
        'patternType': 'recurring',
        'startDate': DateTime.now().toIso8601String(),
        'maxDays': maxDays ?? 180, // Default to 6 months
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      await patternRef.set(patternData);
      
      // Also create the first few days of actual medicine entries for immediate use
      final immediateEntries = _generateImmediateEntries(medicinePattern, 7); // First week
      await _saveStandardBatch(userId, immediateEntries, prescriptionData);
      
      print('✅ Saved recurring pattern and immediate entries');
      
    } catch (e) {
      print('❌ Error saving recurring medicine pattern: $e');
      throw Exception('Failed to save recurring medicine pattern: $e');
    }
  }

  /// Generate immediate medicine entries for the first few days
  List<Map<String, dynamic>> _generateImmediateEntries(
    Map<String, dynamic> pattern, 
    int days
  ) {
    List<Map<String, dynamic>> entries = [];
    final startDate = DateTime.now();
    
    for (int i = 0; i < days; i++) {
      final scheduleDate = startDate.add(Duration(days: i));
      final dateString = scheduleDate.toIso8601String().split('T')[0];
      
      entries.add({
        ...pattern,
        'scheduleDate': dateString,
        'patternId': pattern['id'],
        'isFromPattern': true,
      });
    }
    
    return entries;
  }

  /// Legacy method - kept for backward compatibility
  Future<void> savePrescriptionMedicines(
  String userId, 
  List<Map<String, dynamic>> medicines, 
  Map<String, dynamic> prescriptionData
) async {
  try {
    print('💾 Saving ${medicines.length} medicine entries...');
    
    // Get the current schedule document
    final scheduleDocRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('medicine_schedules')
        .doc('current_schedule');
    
    // Get existing schedule data or create new
    final scheduleDoc = await scheduleDocRef.get();
    Map<String, dynamic> scheduleData;
    
    if (scheduleDoc.exists) {
      scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
    } else {
      scheduleData = {
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'medicines': {},
      };
    }
    
    // Get existing medicines map to preserve existing medicines
    final existingMedicines = Map<String, dynamic>.from(scheduleData['medicines'] ?? {});
    
    // Process each medicine
    for (var medicine in medicines) {
      final medicineId = _firestore.collection('users').doc().id;
      
      // Prepare the medicine data
      final medicineDataWithPrescription = {
        ...medicine,
        'id': medicineId,
        'prescriptionId': prescriptionData['id']?.toString() ?? 'manual_entry',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'isFromPrescription': true,
        'isActive': true,
      };
      
      // Prepare schedule data for this medicine
      final scheduleDate = medicine['scheduleDate'] as String? ?? DateTime.now().toIso8601String().split('T')[0];
      final scheduleDataEntry = {
        'date': scheduleDate,
        'isCompleted': false,
        'completedAt': null,
        'notes': medicine['notes'] ?? '',
      };
      
      // Add to existing medicines map (preserving existing medicines)
      existingMedicines[medicineId] = {
        ...medicineDataWithPrescription,
        'scheduleData': [scheduleDataEntry],
        'scheduleDates': [scheduleDate],
      };
      
      print('📝 Added medicine: ${medicine['name']?.toString() ?? 'Unknown Medicine'} for ${scheduleDate}');
    }
    
    // Update the schedule document with merged medicines
    await scheduleDocRef.set({
      ...scheduleData,
      'medicines': existingMedicines,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // Update the trigger field to refresh StreamBuilder
    await _firestore.collection('users').doc(userId).update({
      'medicationUpdateTrigger': FieldValue.serverTimestamp(),
      'lastPrescriptionSaved': FieldValue.serverTimestamp(),
    });
    
    print('✅ Successfully saved all medicines to Firestore');
    
  } catch (e) {
    print('❌ Error saving prescription medicines: $e');
    throw Exception('Failed to save prescription medicines: $e');
  }
}


  Future<List<Map<String, dynamic>>> getUserMedicines(String userId, {String? dateFilter}) async {
    try {
      // Get the current schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        return [];
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
      
      List<Map<String, dynamic>> result = [];
      
      for (var entry in medicines.entries) {
        final medicineId = entry.key;
        final medicineData = entry.value as Map<String, dynamic>? ?? {};
        
        // Add the medicine ID to the data and ensure voiceFilePath is included
        final medicineWithId = {
          ...medicineData,
          'id': medicineId,
          'voiceFilePath': medicineData['voiceFilePath'], // Ensure voice file path is included
        };
        
        // If a date filter is provided, check if the medicine has data for that date
        if (dateFilter != null) {
          final scheduleDataList = List<Map<String, dynamic>>.from(medicineData['scheduleData'] ?? []);
          final hasDataForDate = scheduleDataList.any((schedule) => schedule['date'] == dateFilter);
          
          if (hasDataForDate) {
            // Get the specific schedule data for this date
            final dateSchedule = scheduleDataList.firstWhere(
              (schedule) => schedule['date'] == dateFilter,
              orElse: () => <String, dynamic>{},
            );
            
            // Merge the medicine data with the date-specific data
            result.add({
              ...medicineWithId,
              'scheduleDate': dateFilter,
              'isCompleted': dateSchedule['isCompleted'] ?? false,
              'completedAt': dateSchedule['completedAt'],
              'notes': dateSchedule['notes'] ?? '',
            });
          }
        } else {
          // No date filter, return all medicines with their latest schedule data
          final scheduleDataList = List<Map<String, dynamic>>.from(medicineData['scheduleData'] ?? []);
          
          if (scheduleDataList.isNotEmpty) {
            // Sort by date to get the most recent
            scheduleDataList.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
            final latestSchedule = scheduleDataList.first;
            
            result.add({
              ...medicineWithId,
              'scheduleDate': latestSchedule['date'],
              'isCompleted': latestSchedule['isCompleted'] ?? false,
              'completedAt': latestSchedule['completedAt'],
              'notes': latestSchedule['notes'] ?? '',
            });
          } else {
            // No schedule data, add the medicine with basic info
            result.add(medicineWithId);
          }
        }
      }
      
      // Sort by creation date (newest first)
      result.sort((a, b) {
        final aCreatedAt = _safeToString(a['createdAt']);
        final bCreatedAt = _safeToString(b['createdAt']);
        return bCreatedAt.compareTo(aCreatedAt);
      });
      
      return result;
    } catch (e) {
      throw Exception('Failed to load medicines: $e');
    }
  }

  Future<void> updateMedicine(String userId, String medicineId, Map<String, dynamic> medicineData) async {
    try {
      // Get the current schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        throw Exception('Medicine schedule not found');
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = Map<String, dynamic>.from(scheduleData['medicines'] ?? {});
      
      if (!medicines.containsKey(medicineId)) {
        throw Exception('Medicine not found in schedule');
      }
      
      // Update the medicine data
      final existingMedicine = medicines[medicineId] as Map<String, dynamic>? ?? {};
      final updatedMedicine = {
        ...existingMedicine,
        ...medicineData,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      
      // Update the schedule document
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .update({
            'medicines.$medicineId': updatedMedicine,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      throw Exception('Failed to update medicine: $e');
    }
  }

  Future<void> deleteMedicine(String userId, String medicineId, {String? selectedDate}) async {
    try {
      print('🗑️ Starting deletion of medicine $medicineId for user $userId');
      
      // If selectedDate is provided, we need to handle date-specific deletion from medicine_schedules
      if (selectedDate != null) {
        await _deleteMedicineForSpecificDate(userId, medicineId, selectedDate);
        return;
      }
      
      // First, check if the medicine exists in the medicine_schedules collection (document-based approach)
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (scheduleDoc.exists) {
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
        final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
        
        if (medicines != null && medicines.containsKey(medicineId)) {
          print('📋 Found medicine in schedule-based collection, deleting...');
          // This is a schedule-based medicine, delete it from the schedule
          await _deleteMedicineFromSchedule(userId, medicineId);
          return;
        }
      }
      
      // If not found in schedule, check the medicines collection (individual documents approach)
      final medicineDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      
      if (!medicineDoc.exists) {
        // Medicine doesn't exist, but this might be expected if it was already deleted
        print('⚠️ Medicine $medicineId not found - may have been already deleted');
        return;
      }
      
      print('📄 Found medicine in individual documents collection, deleting...');
      // Delete the entire medicine document
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(medicineId)
          .delete();
      
      // Update trigger field for StreamBuilder refresh
      await _firestore.collection('users').doc(userId).update({
        'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        'lastMedicineDeleted': FieldValue.serverTimestamp(),
      });
      
      print('✅ Successfully deleted medicine $medicineId from individual documents');
    } catch (e) {
      // If the medicine doesn't exist, don't treat it as an error
      if (e.toString().contains('not-found') || e.toString().contains('not found')) {
        print('⚠️ Medicine $medicineId not found - may have been already deleted');
        return;
      }
      
      // Try to update trigger even if deletion fails
      try {
        await _firestore.collection('users').doc(userId).update({
          'medicationUpdateTrigger': FieldValue.serverTimestamp(),
          'lastMedicineDeleted': FieldValue.serverTimestamp(),
        });
      } catch (triggerError) {
        print('⚠️ Error updating trigger during deletion: $triggerError');
      }
      
      throw Exception('Failed to delete medicine: $e');
    }
  }

  /// Helper method to delete medicine for a specific date from schedule-based medicines
  Future<void> _deleteMedicineForSpecificDate(String userId, String medicineId, String selectedDate) async {
    try {
      print('🔍 Deleting medicine $medicineId for date $selectedDate');
      
      // Get the medicine schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        print('⚠️ Medicine schedule not found');
        return;
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
      
      print('🔍 Found ${medicines?.length ?? 0} medicines in schedule');
      print('🔍 Looking for medicine ID: $medicineId');
      if (medicines != null) {
        print('🔍 Available medicine IDs: ${medicines.keys.toList()}');
      }
      
      if (medicines == null || !medicines.containsKey(medicineId)) {
        print('⚠️ Medicine $medicineId not found in schedule');
        return;
      }
      
      final medicineSchedule = medicines[medicineId] as Map<String, dynamic>? ?? {};
      final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
      final scheduleDataList = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData'] ?? []);
      
      print('🔍 Original schedule dates: $scheduleDates');
      print('🔍 Original schedule data count: ${scheduleDataList.length}');
      
      // Remove the selected date from scheduleDates
      if (scheduleDates.contains(selectedDate)) {
        scheduleDates.remove(selectedDate);
        print('✅ Removed date $selectedDate from scheduleDates');
      } else {
        print('⚠️ Date $selectedDate not found in scheduleDates');
      }
      
      // Remove the schedule data for the selected date
      final originalCount = scheduleDataList.length;
      scheduleDataList.removeWhere((schedule) => schedule['date'] == selectedDate);
      final removedCount = originalCount - scheduleDataList.length;
      print('✅ Removed $removedCount schedule data entries for date $selectedDate');
      
      // Update the medicine schedule
      final updatedMedicineSchedule = {
        ...medicineSchedule,
        'scheduleDates': scheduleDates,
        'scheduleData': scheduleDataList,
      };
      
      // Update the schedule document
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .update({
            'medicines.$medicineId': updatedMedicineSchedule,
          });
      
      // Check if this was the last medicine for this date and clean up if needed
      await _cleanupEmptySchedule(userId, medicineId, selectedDate);
      
      print('✅ Successfully removed medicine $medicineId for date $selectedDate');
    } catch (e) {
      print('❌ Error deleting medicine for specific date: $e');
      throw Exception('Failed to delete medicine for specific date: $e');
    }
  }

  /// Helper method to clean up empty schedule entries
  Future<void> _cleanupEmptySchedule(String userId, String medicineId, String selectedDate) async {
    try {
      // Get the updated schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        // Update trigger field even if document doesn't exist
        await _firestore.collection('users').doc(userId).update({
          'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        });
        return;
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
      
      if (medicines == null || medicines.isEmpty) {
        // No medicines left, delete the entire schedule document
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .delete();
        
        // Update trigger field after document deletion
        await _firestore.collection('users').doc(userId).update({
          'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        });
        
        print('🗑️ Deleted empty schedule document and updated trigger');
        return;
      }
      
      // Check if the specific medicine has no more schedule dates
      if (medicines.containsKey(medicineId)) {
        final medicineSchedule = medicines[medicineId] as Map<String, dynamic>? ?? {};
        final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
        
        if (scheduleDates.isEmpty) {
          // This medicine has no more schedule dates, remove it completely
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('medicine_schedules')
              .doc('current_schedule')
              .update({
                'medicines.$medicineId': FieldValue.delete(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
          
          // Update trigger field
          await _firestore.collection('users').doc(userId).update({
            'medicationUpdateTrigger': FieldValue.serverTimestamp(),
          });
          
          print('🗑️ Removed medicine $medicineId with no schedule dates and updated trigger');
          
          // Recursively check if this was the last medicine
          await _cleanupEmptySchedule(userId, medicineId, selectedDate);
        }
      }
    } catch (e) {
      print('⚠️ Error during schedule cleanup: $e');
      // Don't throw error for cleanup failures, but try to update trigger anyway
      try {
        await _firestore.collection('users').doc(userId).update({
          'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        });
      } catch (triggerError) {
        print('⚠️ Error updating trigger during cleanup: $triggerError');
      }
    }
  }

  /// Helper method to delete medicine completely from schedule-based medicines
  Future<void> _deleteMedicineFromSchedule(String userId, String medicineId) async {
    try {
      // Get the medicine schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        print('⚠️ Medicine schedule not found');
        return;
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
      
      if (medicines == null || !medicines.containsKey(medicineId)) {
        print('⚠️ Medicine $medicineId not found in schedule');
        return;
      }
      
      // Check if this is the last medicine before deletion
      final isLastMedicine = medicines.length == 1;
      
      if (isLastMedicine) {
        // If this is the last medicine, delete the entire schedule document
        // This ensures StreamBuilder properly handles the empty state
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .delete();
        
        print('🗑️ Deleted schedule document (last medicine removed)');
      } else {
        // Remove only the specific medicine from the schedule
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .update({
              'medicines.$medicineId': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
        
        print('✅ Successfully deleted medicine $medicineId from schedule');
      }
      
      // Ensure proper cleanup and trigger updates
      await _ensureProperCleanup(userId);
      
    } catch (e) {
      print('❌ Error deleting medicine from schedule: $e');
      // Try to update trigger even if deletion fails
      try {
        await _firestore.collection('users').doc(userId).update({
          'medicationUpdateTrigger': FieldValue.serverTimestamp(),
          'lastMedicineDeleted': FieldValue.serverTimestamp(),
        });
      } catch (triggerError) {
        print('⚠️ Error updating trigger during schedule deletion: $triggerError');
      }
      throw Exception('Failed to delete medicine from schedule: $e');
    }
  }

  /// Recalculate schedule dates when duration is updated
  Future<void> _recalculateScheduleDates(
    String userId, 
    String medicineKey, 
    Map<String, dynamic> medicineData, 
    String currentDate
  ) async {
    try {
      final duration = medicineData['duration']?.toString() ?? '1 day';
      final durationDays = DurationHelper.parseDurationToDays(duration);
      
      if (durationDays != null && durationDays > 0) {
        // Parse the current date to get start date
        final startDate = DateTime.parse(currentDate);
        final List<String> newScheduleDates = [];
        final List<Map<String, dynamic>> newScheduleData = [];
        
        // Generate schedule dates for the duration period
        for (int i = 0; i < durationDays; i++) {
          final scheduleDate = startDate.add(Duration(days: i));
          final dateString = scheduleDate.toIso8601String().split('T')[0];
          newScheduleDates.add(dateString);
          
          newScheduleData.add({
            'date': dateString,
            'time': medicineData['time']?.toString() ?? '08:00 AM',
            'isCompleted': false,
            'completedAt': null,
          });
        }
        
        // Update the medicine with new schedule dates
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .update({
              'medicines.$medicineKey.scheduleDates': newScheduleDates,
              'medicines.$medicineKey.scheduleData': newScheduleData,
              'medicines.$medicineKey.totalDays': durationDays,
              'medicines.$medicineKey.endDate': newScheduleDates.last,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        
        print('🔄 Recalculated schedule dates for medicine $medicineKey: ${newScheduleDates.length} days');
        print('📅 New schedule dates: ${newScheduleDates.join(', ')}');
      }
    } catch (e) {
      print('❌ Error recalculating schedule dates: $e');
    }
  }

  /// Ensure proper cleanup and trigger updates after medicine deletion
  /// This method helps synchronize StreamBuilder with document operations
  Future<void> _ensureProperCleanup(String userId) async {
    try {
      // Check if there are any medicines left in the schedule
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (scheduleDoc.exists) {
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
        final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
        
        if (medicines == null || medicines.isEmpty) {
          // No medicines left, ensure the document is deleted
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('medicine_schedules')
              .doc('current_schedule')
              .delete();
          
          print('🗑️ Cleaned up empty schedule document');
        }
      }
      
      // Always update trigger fields to ensure StreamBuilder refresh
      await _firestore.collection('users').doc(userId).update({
        'medicationUpdateTrigger': FieldValue.serverTimestamp(),
        'lastMedicineDeleted': FieldValue.serverTimestamp(),
        'lastCleanupTime': FieldValue.serverTimestamp(),
      });
      
      print('🔄 Updated trigger fields for proper StreamBuilder synchronization');
    } catch (e) {
      print('⚠️ Error during cleanup: $e');
    }
  }

  Future<void> deleteAllRelatedMedicines(String userId, String medicineId) async {
    try {
      // First, check if this medicine exists in the medicine_schedules collection
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (scheduleDoc.exists) {
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
        final medicines = scheduleData['medicines'] as Map<String, dynamic>?;
        
        if (medicines != null && medicines.containsKey(medicineId)) {
          // This is a schedule-based medicine, delete it from the schedule
          await _deleteMedicineFromSchedule(userId, medicineId);
          return;
        }
      }
      
      // If not found in schedule, check the medicines collection
      final medicineDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      
      if (!medicineDoc.exists) {
        // Medicine doesn't exist, but this might be expected if it was already deleted
        print('⚠️ Medicine $medicineId not found - may have been already deleted');
        return;
      }
      
      final medicineData = medicineDoc.data() as Map<String, dynamic>? ?? {};
      final isDurationBased = medicineData['isDurationBased'] ?? false;
      final isFromPrescription = medicineData['isFromPrescription'] ?? false;
      final prescriptionId = medicineData['prescriptionId'];
      final medicineName = medicineData['name'];
      
      // Use batch write for efficient deletion
      final batch = _firestore.batch();
      int deletedCount = 0;
      
      if (isDurationBased) {
        // For duration-based medicines, delete all entries with the same name and prescription data
        final relatedDocs = await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicines')
            .where('name', isEqualTo: medicineName)
            .where('isDurationBased', isEqualTo: true)
            .where('prescriptionId', isEqualTo: prescriptionId)
            .get();
        
        for (var doc in relatedDocs.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
        
        print('🗑️ Deleting $deletedCount duration-based medicine entries for $medicineName');
        
      } else if (isFromPrescription && prescriptionId != null) {
        // For prescription medicines, delete all entries with the same prescription ID
        final relatedDocs = await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicines')
            .where('prescriptionId', isEqualTo: prescriptionId)
            .get();
        
        for (var doc in relatedDocs.docs) {
          batch.delete(doc.reference);
          deletedCount++;
        }
        
        print('🗑️ Deleting $deletedCount prescription medicine entries for prescription $prescriptionId');
        
      } else {
        // Fallback: just delete the single medicine
        batch.delete(_firestore
            .collection('users')
            .doc(userId)
            .collection('medicines')
            .doc(medicineId));
        deletedCount = 1;
      }
      
      // Execute the batch
      await batch.commit();
      
      // Update trigger field after batch deletion
      await _firestore.collection('users').doc(userId).update({
        'medicationUpdateTrigger': FieldValue.serverTimestamp(),
      });
      
      print('✅ Successfully deleted $deletedCount medicine entries and updated trigger');
      
    } catch (e) {
      // If the medicine doesn't exist, don't treat it as an error
      if (e.toString().contains('not-found') || e.toString().contains('not found')) {
        print('⚠️ Medicine $medicineId not found - may have been already deleted');
        // Still try to update trigger even if medicine not found
        try {
          await _firestore.collection('users').doc(userId).update({
            'medicationUpdateTrigger': FieldValue.serverTimestamp(),
          });
        } catch (triggerError) {
          print('⚠️ Error updating trigger after medicine not found: $triggerError');
        }
        return;
      }
      throw Exception('Failed to delete related medicines: $e');
    }
  }

  Stream<List<Map<String, dynamic>>> getUserMedicinesStream(String userId, {String? dateFilter}) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('medicine_schedules')
        .doc('current_schedule')
        .snapshots()
        .handleError((error) {
          print('Error in getUserMedicinesStream: $error');
          return <Map<String, dynamic>>[];
        })
        .map((snapshot) {
          if (!snapshot.exists) {
            return <Map<String, dynamic>>[];
          }
          
          final scheduleData = snapshot.data() as Map<String, dynamic>? ?? {};
          final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
          
          List<Map<String, dynamic>> result = [];
          
          for (var entry in medicines.entries) {
            final medicineId = entry.key;
            final medicineData = entry.value as Map<String, dynamic>? ?? {};
            
            // Add the medicine ID to the data and ensure voiceFilePath is included
            final medicineWithId = {
              ...medicineData,
              'id': medicineId,
              'voiceFilePath': medicineData['voiceFilePath'], // Ensure voice file path is included
            };
            
            // If a date filter is provided, check if the medicine has data for that date
            if (dateFilter != null) {
              final scheduleDataList = List<Map<String, dynamic>>.from(medicineData['scheduleData'] ?? []);
              final hasDataForDate = scheduleDataList.any((schedule) => schedule['date'] == dateFilter);
              
              if (hasDataForDate) {
                // Get the specific schedule data for this date
                final dateSchedule = scheduleDataList.firstWhere(
                  (schedule) => schedule['date'] == dateFilter,
                  orElse: () => <String, dynamic>{},
                );
                
                // Merge the medicine data with the date-specific data
                result.add({
                  ...medicineWithId,
                  'scheduleDate': dateFilter,
                  'isCompleted': dateSchedule['isCompleted'] ?? false,
                  'completedAt': dateSchedule['completedAt'],
                  'notes': dateSchedule['notes'] ?? '',
                });
              }
            } else {
              // No date filter, return all medicines with their latest schedule data
              final scheduleDataList = List<Map<String, dynamic>>.from(medicineData['scheduleData'] ?? []);
              
              if (scheduleDataList.isNotEmpty) {
                // Sort by date to get the most recent
                scheduleDataList.sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
                final latestSchedule = scheduleDataList.first;
                
                result.add({
                  ...medicineWithId,
                  'scheduleDate': latestSchedule['date'],
                  'isCompleted': latestSchedule['isCompleted'] ?? false,
                  'completedAt': latestSchedule['completedAt'],
                  'notes': latestSchedule['notes'] ?? '',
                });
              } else {
                // No schedule data, add the medicine with basic info
                result.add(medicineWithId);
              }
            }
          }
          
          // Sort by creation date (newest first)
          result.sort((a, b) {
            final aCreatedAt = _safeToString(a['createdAt']);
            final bCreatedAt = _safeToString(b['createdAt']);
            return bCreatedAt.compareTo(aCreatedAt);
          });
          
          return result;
        });
  }

  Future<Map<String, dynamic>?> getMedicine(String userId, String medicineId) async {
    try {
      // First, check if the medicine exists in the medicine_schedules collection (document-based approach)
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (scheduleDoc.exists) {
        final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
        final medicines = scheduleData['medicines'] as Map<String, dynamic>? ?? {};
        
        // Check if medicineId is a direct key (backward compatibility)
        if (medicines.containsKey(medicineId)) {
          final medicineData = Map<String, dynamic>.from(medicines[medicineId]);
          medicineData['id'] = medicineId;
          return medicineData;
        }
        
        // Search for medicine by ID format: ${entry.key}_$date
        for (var entry in medicines.entries) {
          final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
          final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
          
          for (var date in scheduleDates) {
            final expectedId = '${entry.key}_$date';
            if (expectedId == medicineId) {
              // Found the medicine, return it with the specific date data
              final medicineData = Map<String, dynamic>.from(medicineSchedule);
              medicineData['id'] = medicineId;
              medicineData['scheduleDate'] = date;
              
              // Ensure duration field is properly included
              if (medicineSchedule.containsKey('duration')) {
                medicineData['duration'] = medicineSchedule['duration'];
                print('🔍 Retrieved duration from schedule: "${medicineSchedule['duration']}"');
              }
              
              // Get the specific schedule data for this date
              final scheduleData = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData'] ?? []);
              final dateSchedule = scheduleData.firstWhere(
                (schedule) => schedule['date'] == date,
                orElse: () => {
                  'date': date,
                  'time': medicineSchedule['time']?.toString() ?? '08:00 AM',
                  'isCompleted': false,
                  'completedAt': null
                },
              );
              
              // Add date-specific data
              medicineData['isCompleted'] = dateSchedule['isCompleted'] ?? false;
              medicineData['completedAt'] = dateSchedule['completedAt'];
              
              print('🔍 Returning medicine data with duration: "${medicineData['duration']}"');
              return medicineData;
            }
          }
        }
      }
      
      // If not found in schedule, check the medicines collection (backward compatibility)
      final medicineDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicines')
          .doc(medicineId)
          .get();
      
      if (medicineDoc.exists) {
        final data = medicineDoc.data();
        data?['id'] = medicineId;
        return data;
      }
      
      return null;
    } catch (e) {
      print('Error getting medicine: $e');
      return null;
    }
  }

  // New method to fetch medicines from the top-level 'medicines' collection
  Future<List<Map<String, dynamic>>> getMedicinesCollection() async {
    try {
      final querySnapshot = await _firestore
          .collection('medicines')
          .get();
          
      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        // Make sure ID is included
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      print('Error fetching medicines collection: $e');
      throw Exception('Failed to load medicines: $e');
    }
  }

  // Returns all food-drug interactions without filtering
  Future<List<FoodDrugInteraction>> getFoodDrugInteractions() async {
    try {
      final medicinesData = await getMedicinesCollection();
      return medicinesData.map((data) {
        return FoodDrugInteraction.fromJson({
          'id': data['id'] ?? '',
          'drugName': data['name'] ?? data['drugName'] ?? data['id'] ?? '',
          'description': data['description'] ?? '',
          'foodToTake': data['foodToTake'] ?? '',
          'foodToAvoid': data['foodToAvoid'] ?? '',
          'interactingWith': data['interactingWith'] ?? '',
          'timeToTake': data['timeToTake'] ?? '',
          'searchKey': data['searchKey'] ?? '',
          'url': data['url'] ?? 'na',
          'url1': data['url1'] ?? 'na',
          'url2': data['url2'] ?? 'na',
          'url3': data['url3'] ?? 'na',
        });
      }).toList();
    } catch (e) {
      print('Error fetching drug-food interactions: $e');
      throw Exception('Failed to load interactions: $e');
    }
  }

  /// Document-based approach: Store all medicines in a single user document
  /// This dramatically reduces writes and maintains query flexibility
  Future<void> saveMedicinesDocumentBased(
    String userId, 
    List<Map<String, dynamic>> medicines, 
    Map<String, dynamic> prescriptionData,
    {Function(int current, int total)? onProgress}
  ) async {
    try {
      print('📄 Starting document-based save for ${medicines.length} medicine entries...');
      
      // Group medicines by their properties to create compressed schedules
      final Map<String, Map<String, dynamic>> medicineSchedules = {};
      
      for (var medicine in medicines) {
        print('🔍 Processing medicine: ${medicine['name']}');
        
        // Ensure all required fields have default values to prevent null errors
        final name = medicine['name']?.toString() ?? 'Unknown Medicine';
        final dosage = medicine['dosage']?.toString() ?? '1 tablet';
        final frequency = medicine['frequency']?.toString() ?? 'Once Daily';
        final timing = medicine['timing']?.toString() ?? 'Morning';
        final time = medicine['time']?.toString() ?? '08:00 AM';
        final type = medicine['type']?.toString() ?? 'Tablet';
        final instructions = medicine['instructions']?.toString() ?? '';
        final foodInstructions = medicine['foodInstructions']?.toString() ?? 'Anytime';
        final duration = medicine['duration']?.toString() ?? '1 day';
        final scheduleDate = medicine['scheduleDate']?.toString() ?? DateTime.now().toIso8601String().split('T')[0];
        
        print('🔍 Processed values - name: $name, dosage: $dosage, timing: $timing, time: $time');
        
        // Create a unique key for each medicine type and time
        final key = '${name}_${dosage}_${frequency}_${timing}_${time}';
        print('🔍 Created key: $key');
        
        if (!medicineSchedules.containsKey(key)) {
          // Initialize medicine schedule
          medicineSchedules[key] = {
            'name': name,
            'dosage': dosage,
            'type': type,
            'frequency': frequency,
            'timing': timing,
            'time': time,
            'instructions': instructions,
            'foodInstructions': foodInstructions,
            'duration': duration,
            'isFromPrescription': medicine['isFromPrescription'] ?? false,
            'isActive': medicine['isActive'] ?? true,
            'prescriptionData': prescriptionData,
            'frontImagePath': medicine['frontImagePath'], // Include image paths
            'backImagePath': medicine['backImagePath'], // Include image paths
            'voiceFilePath': medicine['voiceFilePath'], // Include voice recording path
            'scheduleDates': <String>[], // Array of dates when this medicine should be taken
            'scheduleData': <Map<String, dynamic>>[], // Detailed schedule data
            'totalDays': 0,
            'startDate': scheduleDate,
            'endDate': scheduleDate,
          };
          print('🔍 Created new medicine schedule for key: $key');
        }
        
        // Add this date to the schedule
        final schedule = medicineSchedules[key]!;
        schedule['scheduleDates']!.add(scheduleDate);
        schedule['scheduleData']!.add({
          'date': scheduleDate,
          'time': time,
          'isCompleted': medicine['isCompleted'] ?? false,
          'completedAt': medicine['completedAt'],
        });
        print('🔍 Added schedule data for date: $scheduleDate with time: $time');
        
        // Update date range
        if (scheduleDate.compareTo(schedule['startDate']) < 0) {
          schedule['startDate'] = scheduleDate;
        }
        if (scheduleDate.compareTo(schedule['endDate']) > 0) {
          schedule['endDate'] = scheduleDate;
        }
        schedule['totalDays'] = schedule['scheduleDates']!.length;
      }
      
      // Get existing schedule data to preserve existing medicines
      final scheduleDocRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule');
      
      final scheduleDoc = await scheduleDocRef.get();
      Map<String, dynamic> existingScheduleData;
      
      if (scheduleDoc.exists) {
        existingScheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      } else {
        existingScheduleData = {
          'userId': userId,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'medicines': {},
          'totalMedicines': 0,
          'totalEntries': 0,
          'isActive': true,
        };
      }
      
      // Merge with existing medicines
      final existingMedicines = Map<String, dynamic>.from(existingScheduleData['medicines'] ?? {});

      // Preserve existing voice recordings when new data doesn't include them
      medicineSchedules.forEach((key, newData) {
        final incomingVoicePath = newData['voiceFilePath'];
        final existingEntry = existingMedicines[key];
        final existingVoicePath = existingEntry is Map<String, dynamic> ? existingEntry['voiceFilePath'] : null;

        if ((incomingVoicePath == null || (incomingVoicePath is String && incomingVoicePath.isEmpty)) &&
            existingVoicePath != null &&
            existingVoicePath.toString().isNotEmpty) {
          newData['voiceFilePath'] = existingVoicePath;
        }
      });

      existingMedicines.addAll(medicineSchedules);
      
      // Create the updated medicine document
      final updatedMedicineDoc = {
        ...existingScheduleData,
        'prescriptionId': prescriptionData['id']?.toString() ?? 'manual_entry',
        'medicines': existingMedicines,
        'totalMedicines': existingMedicines.length,
        'totalEntries': (existingScheduleData['totalEntries'] ?? 0) + medicines.length,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'isActive': true,
      };
      
      // Save to Firestore - merge with existing data
      await scheduleDocRef.set(updatedMedicineDoc, SetOptions(merge: true));
      
      print('✅ Document-based save completed with ${medicineSchedules.length} medicine schedules');
      print('📊 Reduced writes from ${medicines.length} to 1 (${((1 / medicines.length) * 100).toStringAsFixed(1)}% reduction)');
      
    } catch (e) {
      print('❌ Error in document-based save: $e');
      throw Exception('Failed to save medicines document-based: $e');
    }
  }

  /// Fetch medicines for a specific date using document-based approach
  Future<List<Map<String, dynamic>>> getMedicinesForDateDocumentBased(
    String userId, 
    String date
  ) async {
    try {
      print('📅 Fetching medicines for date: $date');
      
      final docSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!docSnapshot.exists) {
        print('📄 No medicine schedule found for user');
        return [];
      }
      
      final data = docSnapshot.data()!;
      final medicines = data['medicines'] as Map<String, dynamic>? ?? {};
      final List<Map<String, dynamic>> medicinesForDate = [];
      
      // Iterate through each medicine schedule
      for (var entry in medicines.entries) {
        final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
        final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
        
        // Check if this medicine is scheduled for the requested date
        if (scheduleDates.contains(date)) {
          // Find the specific schedule data for this date
          final scheduleData = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData'] ?? []);
          final dateSchedule = scheduleData.firstWhere(
            (schedule) => schedule['date'] == date,
            orElse: () => {
              'date': date, 
              'time': medicineSchedule['time']?.toString() ?? '08:00 AM', 
              'isCompleted': false, 
              'completedAt': null
            },
          );
          
          // Create medicine entry for this date
          medicinesForDate.add({
            'id': '${entry.key}_$date', // Generate unique ID
            'name': medicineSchedule['name']?.toString() ?? 'Unknown Medicine',
            'dosage': medicineSchedule['dosage']?.toString() ?? '1 tablet',
            'type': medicineSchedule['type']?.toString() ?? 'Tablet',
            'frequency': medicineSchedule['frequency']?.toString() ?? 'Once Daily',
            'timing': medicineSchedule['timing']?.toString() ?? 'Morning',
            'time': dateSchedule['time']?.toString() ?? medicineSchedule['time']?.toString() ?? '08:00 AM',
            'instructions': medicineSchedule['instructions']?.toString() ?? '',
            'foodInstructions': medicineSchedule['foodInstructions']?.toString() ?? 'Anytime',
            'scheduleDate': date,
            'isCompleted': dateSchedule['isCompleted'] ?? false,
            'completedAt': dateSchedule['completedAt'],
            'isFromPrescription': medicineSchedule['isFromPrescription'] ?? false,
            'isActive': medicineSchedule['isActive'] ?? true,
            'prescriptionData': medicineSchedule['prescriptionData'] ?? {},
          });
        }
      }
      
      print('📋 Found ${medicinesForDate.length} medicines for $date');
      return medicinesForDate;
      
    } catch (e) {
      print('❌ Error fetching medicines for date: $e');
      throw Exception('Failed to fetch medicines for date: $e');
    }
  }

  /// Fetch all medicines within a date range using document-based approach
  Future<List<Map<String, dynamic>>> getMedicinesInDateRangeDocumentBased(
    String userId, 
    String startDate, 
    String endDate
  ) async {
    try {
      print('📅 Fetching medicines from $startDate to $endDate');
      
      final docSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!docSnapshot.exists) {
        return [];
      }
      
      final data = docSnapshot.data()!;
      final medicines = data['medicines'] as Map<String, dynamic>? ?? {};
      final List<Map<String, dynamic>> medicinesInRange = [];
      
      // Iterate through each medicine schedule
      for (var entry in medicines.entries) {
        final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
        final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
        
        // Filter dates within the range
        final datesInRange = scheduleDates.where((date) => 
          date.compareTo(startDate) >= 0 && date.compareTo(endDate) <= 0
        ).toList();
        
        // Create entries for each date in range
        for (var date in datesInRange) {
          final scheduleData = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData'] ?? []);
          final dateSchedule = scheduleData.firstWhere(
            (schedule) => schedule['date'] == date,
            orElse: () => {
              'date': date, 
              'time': medicineSchedule['time']?.toString() ?? '08:00 AM', 
              'isCompleted': false, 
              'completedAt': null
            },
          );
          
          medicinesInRange.add({
            'id': '${entry.key}_$date',
            'name': medicineSchedule['name']?.toString() ?? 'Unknown Medicine',
            'dosage': medicineSchedule['dosage']?.toString() ?? '1 tablet',
            'type': medicineSchedule['type']?.toString() ?? 'Tablet',
            'frequency': medicineSchedule['frequency']?.toString() ?? 'Once Daily',
            'timing': medicineSchedule['timing']?.toString() ?? 'Morning',
            'time': dateSchedule['time']?.toString() ?? medicineSchedule['time']?.toString() ?? '08:00 AM',
            'instructions': medicineSchedule['instructions']?.toString() ?? '',
            'foodInstructions': medicineSchedule['foodInstructions']?.toString() ?? 'Anytime',
            'scheduleDate': date,
            'isCompleted': dateSchedule['isCompleted'] ?? false,
            'completedAt': dateSchedule['completedAt'],
            'isFromPrescription': medicineSchedule['isFromPrescription'] ?? false,
            'isActive': medicineSchedule['isActive'] ?? true,
            'prescriptionData': medicineSchedule['prescriptionData'] ?? {},
          });
        }
      }
      
      print('📋 Found ${medicinesInRange.length} medicines in date range');
      return medicinesInRange;
      
    } catch (e) {
      print('❌ Error fetching medicines in date range: $e');
      throw Exception('Failed to fetch medicines in date range: $e');
    }
  }

  /// Update medicine completion status for a specific date
  Future<void> updateMedicineCompletionDocumentBased(
    String userId, 
    String medicineId, 
    String date, 
    bool isCompleted, 
    {DateTime? completedAt}
  ) async {
    try {
      print('✅ Updating completion status for medicine $medicineId on $date');
      
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule');
      
      // Get current document
      final docSnapshot = await docRef.get();
      if (!docSnapshot.exists) {
        print('⚠️ Medicine schedule not found');
        return;
      }
      
      final data = docSnapshot.data()!;
      final medicines = Map<String, dynamic>.from(data['medicines']);
      
      // Try to find the medicine by the provided ID first
      String? foundKey;
      Map<String, dynamic>? foundMedicine;
      
      // First, try exact match
      if (medicines.containsKey(medicineId)) {
        foundKey = medicineId;
        foundMedicine = Map<String, dynamic>.from(medicines[medicineId]);
      } else {
        // If not found, try to find by partial match (for composite IDs)
        for (var entry in medicines.entries) {
          final key = entry.key;
          // Check if the medicineId is part of the key (for composite IDs)
          if (key.startsWith(medicineId) || medicineId.startsWith(key)) {
            foundKey = key;
            foundMedicine = Map<String, dynamic>.from(entry.value);
            print('🔧 Found medicine by partial match: $key for medicineId: $medicineId');
            break;
          }
        }
      }
      
      if (foundKey != null && foundMedicine != null) {
        final scheduleData = List<Map<String, dynamic>>.from(foundMedicine['scheduleData']);
        
        // Update the specific date's completion status
        bool dateFound = false;
        for (int i = 0; i < scheduleData.length; i++) {
          if (scheduleData[i]['date'] == date) {
            scheduleData[i]['isCompleted'] = isCompleted;
            scheduleData[i]['completedAt'] = completedAt?.toIso8601String();
            dateFound = true;
            print('✅ Updated completion status for date $date: $isCompleted');
            break;
          }
        }
        
        if (!dateFound) {
          print('⚠️ Date $date not found in schedule data, adding new entry');
          // Add new date entry if not found
          scheduleData.add({
            'date': date,
            'time': foundMedicine['time'],
            'isCompleted': isCompleted,
            'completedAt': completedAt?.toIso8601String(),
          });
        }
        
        foundMedicine['scheduleData'] = scheduleData;
        medicines[foundKey] = foundMedicine;
        
        // Update the document
        await docRef.update({
          'medicines': medicines,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        print('✅ Successfully updated completion status for medicine $foundKey');
      } else {
        print('⚠️ Medicine $medicineId not found in schedule');
        // Don't throw exception, just log the warning
      }
      
    } catch (e) {
      print('❌ Error updating medicine completion: $e');
      throw Exception('Failed to update medicine completion: $e');
    }
  }

  /// Get medicine statistics and summary
  Future<Map<String, dynamic>> getMedicineStatsDocumentBased(String userId) async {
    try {
      final docSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!docSnapshot.exists) {
        return {
          'totalMedicines': 0,
          'totalEntries': 0,
          'completedToday': 0,
          'pendingToday': 0,
          'completionRate': 0.0,
        };
      }
      
      final data = docSnapshot.data()!;
      final medicines = data['medicines'] as Map<String, dynamic>? ?? {};
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      int completedToday = 0;
      int pendingToday = 0;
      int totalCompleted = 0;
      int totalEntries = 0;
      
      for (var entry in medicines.entries) {
        final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
        final scheduleData = List<Map<String, dynamic>>.from(medicineSchedule['scheduleData']);
        
        for (var schedule in scheduleData) {
          totalEntries++;
          if (schedule['isCompleted'] == true) {
            totalCompleted++;
          }
          
          if (schedule['date'] == today) {
            if (schedule['isCompleted'] == true) {
              completedToday++;
            } else {
              pendingToday++;
            }
          }
        }
      }
      
      return {
        'totalMedicines': medicines.length,
        'totalEntries': totalEntries,
        'completedToday': completedToday,
        'pendingToday': pendingToday,
        'completionRate': totalEntries > 0 ? (totalCompleted / totalEntries) : 0.0,
        'totalCompleted': totalCompleted,
      };
      
    } catch (e) {
      print('❌ Error getting medicine stats: $e');
      throw Exception('Failed to get medicine stats: $e');
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

  /// Update medicine in document-based approach
  /// This method finds the medicine by its ID and updates it while preserving other medicines
  Future<void> updateMedicineDocumentBased(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      print('🔍 Updating medicine $medicineId in document-based approach...');
      
      // Get the current schedule document
      final scheduleDoc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('medicine_schedules')
          .doc('current_schedule')
          .get();
      
      if (!scheduleDoc.exists) {
        throw Exception('Medicine schedule not found');
      }
      
      final scheduleData = scheduleDoc.data() as Map<String, dynamic>? ?? {};
      final medicines = Map<String, dynamic>.from(scheduleData['medicines'] ?? {});
      
      // Find the medicine by its ID
      // The medicineId format is: ${entry.key}_$date
      String? foundKey;
      String? foundDate;
      
      // Extract the key and date from the medicineId
      for (var entry in medicines.entries) {
        final medicineSchedule = entry.value as Map<String, dynamic>? ?? {};
        final scheduleDates = List<String>.from((medicineSchedule['scheduleDates'] ?? []).where((item) => item != null).cast<String>());
        
        for (var date in scheduleDates) {
          final expectedId = '${entry.key}_$date';
          if (expectedId == medicineId) {
            foundKey = entry.key;
            foundDate = date;
            break;
          }
        }
        if (foundKey != null) break;
      }
      
      if (foundKey == null) {
        throw Exception('Medicine not found in schedule');
      }
      
      // Check if the medicine properties have changed (which would change the key)
      final existingMedicine = medicines[foundKey] as Map<String, dynamic>? ?? {};
      final name = medicineData['name']?.toString() ?? existingMedicine['name']?.toString() ?? 'Unknown Medicine';
      final dosage = medicineData['dosage']?.toString() ?? existingMedicine['dosage']?.toString() ?? '1 tablet';
      final frequency = medicineData['frequency']?.toString() ?? existingMedicine['frequency']?.toString() ?? 'Once Daily';
      final timing = medicineData['timing']?.toString() ?? existingMedicine['timing']?.toString() ?? 'Morning';
      final time = medicineData['time']?.toString() ?? existingMedicine['time']?.toString() ?? '08:00 AM';
      
      final newKey = '${name}_${dosage}_${frequency}_${timing}_${time}';
      
      print('🔍 Duration update - Existing: "${existingMedicine['duration']}", New: "${medicineData['duration']}"');
      print('🔍 Key comparison - Old: $foundKey, New: $newKey');
      
      // Check if duration has changed
      final existingDuration = existingMedicine['duration']?.toString() ?? '';
      final newDuration = medicineData['duration']?.toString() ?? '';
      final durationChanged = existingDuration != newDuration;
      
      print('🔍 Duration changed: $durationChanged ($existingDuration -> $newDuration)');
      
      // Recreate the entry if the key has changed (name, dosage, frequency, timing, or time changed)
      if (newKey != foundKey) {
        // Key has changed (not just duration), need to create new entry and remove old one
        print('🔍 Medicine key changed from $foundKey to $newKey, recreating entry...');
        
        // Create new medicine entry
        // Preserve all existing scheduleData but update times
        final existingScheduleData = List<Map<String, dynamic>>.from(existingMedicine['scheduleData'] ?? []);
        final updatedScheduleData = existingScheduleData.map((schedule) => {
          ...schedule,
          'time': time, // Update time for all schedule entries
        }).toList();
        print('🕐 Updated all scheduleData entries with new time: $time (${updatedScheduleData.length} entries)');
        
        final newMedicine = {
          'name': name,
          'dosage': dosage,
          'type': medicineData['type']?.toString() ?? existingMedicine['type']?.toString() ?? 'Tablet',
          'frequency': frequency,
          'timing': timing,
          'time': time,
          'instructions': medicineData['instructions']?.toString() ?? existingMedicine['instructions']?.toString() ?? '',
          'foodInstructions': medicineData['foodInstructions']?.toString() ?? existingMedicine['foodInstructions']?.toString() ?? 'Anytime',
          'duration': medicineData['duration']?.toString() ?? existingMedicine['duration']?.toString() ?? '1 day',
          'isFromPrescription': medicineData['isFromPrescription'] ?? existingMedicine['isFromPrescription'] ?? false,
          'isActive': medicineData['isActive'] ?? existingMedicine['isActive'] ?? true,
          'prescriptionData': medicineData['prescriptionData'] ?? existingMedicine['prescriptionData'],
          'frontImagePath': medicineData['frontImagePath'] ?? existingMedicine['frontImagePath'], // Include image paths
          'backImagePath': medicineData['backImagePath'] ?? existingMedicine['backImagePath'], // Include image paths
          'voiceFilePath': medicineData['voiceFilePath'] ?? existingMedicine['voiceFilePath'], // Include voice file path
          'createdAt': existingMedicine['createdAt'], // Preserve original creation time
          'scheduleDates': existingMedicine['scheduleDates'] ?? [foundDate], // Preserve all schedule dates
          'scheduleData': updatedScheduleData, // Use updated schedule data with new times
          'totalDays': existingMedicine['totalDays'] ?? 1,
          'startDate': existingMedicine['startDate'] ?? foundDate,
          'endDate': existingMedicine['endDate'] ?? foundDate,
        };
        
        // Remove old entry and add new one
        medicines.remove(foundKey);
        medicines[newKey] = newMedicine;
      } else {
        // Key hasn't changed or it's just a duration update, update the existing entry
        
        // Update the existing medicine data while preserving the key
        // Also update the scheduleData entries to reflect the new time
        final updatedScheduleData = List<Map<String, dynamic>>.from(existingMedicine['scheduleData'] ?? []);
        for (int i = 0; i < updatedScheduleData.length; i++) {
          updatedScheduleData[i]['time'] = time;
        }
        
        medicines[foundKey] = {
          ...existingMedicine,
          'name': name,
          'dosage': dosage,
          'type': medicineData['type']?.toString() ?? existingMedicine['type']?.toString() ?? 'Tablet',
          'frequency': frequency,
          'timing': timing,
          'time': time,
          'instructions': medicineData['instructions']?.toString() ?? existingMedicine['instructions']?.toString() ?? '',
          'foodInstructions': medicineData['foodInstructions']?.toString() ?? existingMedicine['foodInstructions']?.toString() ?? 'Anytime',
          'duration': medicineData['duration']?.toString() ?? existingMedicine['duration']?.toString() ?? '1 day',
          'isFromPrescription': medicineData['isFromPrescription'] ?? existingMedicine['isFromPrescription'] ?? false,
          'isActive': medicineData['isActive'] ?? existingMedicine['isActive'] ?? true,
          'prescriptionData': medicineData['prescriptionData'] ?? existingMedicine['prescriptionData'],
          'frontImagePath': medicineData['frontImagePath'] ?? existingMedicine['frontImagePath'], // Include image paths
          'backImagePath': medicineData['backImagePath'] ?? existingMedicine['backImagePath'], // Include image paths
          'voiceFilePath': medicineData['voiceFilePath'] ?? existingMedicine['voiceFilePath'], // Include voice file path
          'scheduleData': updatedScheduleData, // Update scheduleData with new time
          'scheduleDates': existingMedicine['scheduleDates'], // Preserve scheduleDates array
          'lastUpdated': DateTime.now().toIso8601String(),
        };
      }
      
      // Update the schedule document
      // If the key changed, we need to remove the old key and add the new one
      if (newKey != foundKey) {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .update({
              'medicines.$newKey': medicines[newKey],
              'medicines.$foundKey': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
      } else {
        await _firestore
            .collection('users')
            .doc(userId)
            .collection('medicine_schedules')
            .doc('current_schedule')
            .update({
              'medicines.$foundKey': medicines[foundKey],
              'updatedAt': FieldValue.serverTimestamp(),
            });
      }
      
      // Update the user document to trigger UI refresh
      await _firestore
          .collection('users')
          .doc(userId)
          .update({
            'medicationUpdateTrigger': FieldValue.serverTimestamp(),
            'lastMedicineUpdated': FieldValue.serverTimestamp(), // Additional trigger for updates
            'lastDurationUpdate': FieldValue.serverTimestamp(), // Specific trigger for duration updates
          });
      
      print('✅ Successfully updated medicine $medicineId (key: $foundKey, date: $foundDate)');
      print('🔍 Key remained the same, duration updated: "${existingMedicine['duration']}" -> "${medicineData['duration']}"');
      print('🔍 Preserved createdAt: "${existingMedicine['createdAt']}"');
      
      // Force a small delay to ensure the update is processed
      await Future.delayed(Duration(milliseconds: 100));
      
      // Verify the update by re-fetching the medicine data
      try {
        final verificationData = await getMedicine(userId, medicineId);
        if (verificationData != null) {
          print('🔍 Verification - Updated medicine duration: "${verificationData['duration']}"');
          if (verificationData['duration']?.toString() != newDuration) {
            print('⚠️ Warning: Duration may not have been updated properly');
          } else {
            print('✅ Duration update verified successfully');
          }
        }
      } catch (e) {
        print('⚠️ Could not verify duration update: $e');
      }
    } catch (e) {
      print('❌ Error updating medicine: $e');
      throw Exception('Failed to update medicine: $e');
    }
  }

  /// Local-first medicine update for better performance
  /// Saves to SharedPreferences immediately and syncs to Firebase in background
  Future<void> updateMedicineLocalFirst(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      print('🚀 Starting local-first medicine update for: $medicineId');
      
      // Ensure the medicine data includes the ID to prevent duplicates
      final updatedMedicineData = {
        ...medicineData,
        'id': medicineId, // Preserve the existing ID
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      
      // Step 1: Save to SharedPreferences immediately for instant UI update
      try {
        await saveMedicineToLocalStorage(userId, medicineId, updatedMedicineData);
        print('✅ Saved to local storage immediately');
      } catch (localError) {
        print('⚠️ Local storage failed, falling back to Firebase only: $localError');
        // If local storage fails, still try Firebase update
        await updateMedicineDocumentBased(userId, medicineId, updatedMedicineData);
        return;
      }
      
      // Step 2: Update Firebase in background (non-blocking)
      _updateFirebaseInBackground(userId, medicineId, updatedMedicineData);
      
    } catch (e) {
      print('❌ Error in local-first update: $e');
      throw Exception('Failed to update medicine: $e');
    }
  }

  /// Save medicine data to SharedPreferences for instant access
  Future<void> saveMedicineToLocalStorage(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'medicine_${userId}_$medicineId';
      
      // Convert Firebase Timestamps to ISO strings for JSON serialization
      final serializableData = _convertTimestampsToIsoStrings(medicineData);
      
      // Convert medicine data to JSON string
      final medicineJson = jsonEncode(serializableData);
      await prefs.setString(key, medicineJson);
      
      // Also save to a list of updated medicines for sync tracking
      final updatedMedicinesKey = 'updated_medicines_$userId';
      List<String> updatedMedicines = prefs.getStringList(updatedMedicinesKey) ?? [];
      if (!updatedMedicines.contains(medicineId)) {
        updatedMedicines.add(medicineId);
        await prefs.setStringList(updatedMedicinesKey, updatedMedicines);
      }
      
      // Set last update timestamp
      await prefs.setString('last_medicine_update_$userId', DateTime.now().toIso8601String());
      
      print('💾 Saved medicine to local storage with key: $key');
    } catch (e) {
      print('❌ Error saving to local storage: $e');
      throw e;
    }
  }

  /// Convert Firebase Timestamps to ISO strings for JSON serialization
  Map<String, dynamic> _convertTimestampsToIsoStrings(Map<String, dynamic> data) {
    final converted = <String, dynamic>{};
    
    for (var entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is Timestamp) {
        // Convert Timestamp to ISO string
        converted[key] = value.toDate().toIso8601String();
      } else if (value is Map<String, dynamic>) {
        // Recursively convert nested maps
        converted[key] = _convertTimestampsToIsoStrings(value);
      } else if (value is List) {
        // Handle lists that might contain Timestamps
        converted[key] = value.map((item) {
          if (item is Timestamp) {
            return item.toDate().toIso8601String();
          } else if (item is Map<String, dynamic>) {
            return _convertTimestampsToIsoStrings(item);
          }
          return item;
        }).toList();
      } else {
        // Keep other values as is
        converted[key] = value;
      }
    }
    
    return converted;
  }

  /// Update Firebase in background without blocking the UI
  Future<void> _updateFirebaseInBackground(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      print('🔄 Starting background Firebase update for: $medicineId');
      
      // Add a small delay to ensure UI updates first
      await Future.delayed(Duration(milliseconds: 100));
      
      // Use the existing update method
      await updateMedicineDocumentBased(userId, medicineId, medicineData);
      
      // Remove from updated medicines list after successful sync
      final prefs = await SharedPreferences.getInstance();
      final updatedMedicinesKey = 'updated_medicines_$userId';
      List<String> updatedMedicines = prefs.getStringList(updatedMedicinesKey) ?? [];
      updatedMedicines.remove(medicineId);
      await prefs.setStringList(updatedMedicinesKey, updatedMedicines);
      
      print('✅ Background Firebase update completed for: $medicineId');
    } catch (e) {
      print('❌ Background Firebase update failed: $e');
      // Don't throw here as this is background operation
      // The data is already saved locally
    }
  }

  /// Get medicine data with local-first approach
  Future<Map<String, dynamic>?> getMedicineLocalFirst(String userId, String medicineId) async {
    try {
      // Step 1: Try to get from local storage first (fastest)
      try {
        final localData = await _getMedicineFromLocalStorage(userId, medicineId);
        if (localData != null) {
          print('📱 Retrieved medicine from local storage: $medicineId');
          return localData;
        }
      } catch (localError) {
        print('⚠️ Local storage read failed, falling back to Firebase: $localError');
      }
      
      // Step 2: Fallback to Firebase
      print('🌐 Local data not found, fetching from Firebase: $medicineId');
      final firebaseData = await getMedicine(userId, medicineId);
      
      // Step 3: Cache the Firebase data locally for future use
      if (firebaseData != null) {
        try {
          await _saveMedicineToLocalStorage(userId, medicineId, firebaseData);
        } catch (cacheError) {
          print('⚠️ Failed to cache Firebase data locally: $cacheError');
          // Continue without caching
        }
      }
      
      return firebaseData;
    } catch (e) {
      print('❌ Error in local-first get: $e');
      return null;
    }
  }

  /// Get medicine data from SharedPreferences
  Future<Map<String, dynamic>?> _getMedicineFromLocalStorage(String userId, String medicineId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'medicine_${userId}_$medicineId';
      
      final medicineJson = prefs.getString(key);
      if (medicineJson != null) {
        final medicineData = jsonDecode(medicineJson) as Map<String, dynamic>;
        
        // Convert ISO string timestamps back to DateTime objects for consistency
        final convertedData = _convertIsoStringsToDateTime(medicineData);
        return convertedData;
      }
      
      return null;
    } catch (e) {
      print('❌ Error reading from local storage: $e');
      return null;
    }
  }

  /// Save medicine data to SharedPreferences
  Future<void> _saveMedicineToLocalStorage(
    String userId, 
    String medicineId, 
    Map<String, dynamic> medicineData
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'medicine_${userId}_$medicineId';
      
      // Convert medicine data to JSON string
      final medicineJson = jsonEncode(medicineData);
      await prefs.setString(key, medicineJson);
      
      // Also save to a list of medicines for tracking
      final medicinesKey = 'medicines_$userId';
      List<String> medicines = prefs.getStringList(medicinesKey) ?? [];
      if (!medicines.contains(medicineId)) {
        medicines.add(medicineId);
        await prefs.setStringList(medicinesKey, medicines);
      }
      
      // Set last update timestamp
      await prefs.setString('last_medicine_update_$userId', DateTime.now().toIso8601String());
      
      print('💾 Saved medicine to local storage with key: $key');
    } catch (e) {
      print('❌ Error saving to local storage: $e');
      throw e;
    }
  }

  /// Convert ISO string timestamps back to DateTime objects
  Map<String, dynamic> _convertIsoStringsToDateTime(Map<String, dynamic> data) {
    final converted = <String, dynamic>{};
    
    for (var entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      
      if (value is String && _isIsoDateTimeString(value)) {
        // Convert ISO string to DateTime
        try {
          converted[key] = DateTime.parse(value);
        } catch (e) {
          // If parsing fails, keep as string
          converted[key] = value;
        }
      } else if (value is Map<String, dynamic>) {
        // Recursively convert nested maps
        converted[key] = _convertIsoStringsToDateTime(value);
      } else if (value is List) {
        // Handle lists that might contain ISO strings
        converted[key] = value.map((item) {
          if (item is String && _isIsoDateTimeString(item)) {
            try {
              return DateTime.parse(item);
            } catch (e) {
              return item;
            }
          } else if (item is Map<String, dynamic>) {
            return _convertIsoStringsToDateTime(item);
          }
          return item;
        }).toList();
      } else {
        // Keep other values as is
        converted[key] = value;
      }
    }
    
    return converted;
  }

  /// Check if a string is an ISO datetime string
  bool _isIsoDateTimeString(String value) {
    // Simple check for ISO datetime format (YYYY-MM-DDTHH:mm:ss)
    final isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');
    return isoPattern.hasMatch(value);
  }

  /// Sync all locally updated medicines to Firebase
  Future<void> syncLocalUpdatesToFirebase(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updatedMedicinesKey = 'updated_medicines_$userId';
      List<String> updatedMedicines = prefs.getStringList(updatedMedicinesKey) ?? [];
      
      if (updatedMedicines.isEmpty) {
        print('ℹ️ No local updates to sync');
        return;
      }
      
      print('🔄 Syncing ${updatedMedicines.length} local updates to Firebase');
      
      for (String medicineId in updatedMedicines) {
        try {
          final localData = await _getMedicineFromLocalStorage(userId, medicineId);
          if (localData != null) {
            await updateMedicineDocumentBased(userId, medicineId, localData);
            print('✅ Synced medicine: $medicineId');
          }
        } catch (e) {
          print('❌ Failed to sync medicine $medicineId: $e');
        }
      }
      
      // Clear the updated medicines list after successful sync
      await prefs.setStringList(updatedMedicinesKey, []);
      print('✅ All local updates synced to Firebase');
      
    } catch (e) {
      print('❌ Error syncing local updates: $e');
    }
  }
}