import 'package:flutter/material.dart';

class TimingUtils {
  static String convertTimingToTime(String timing, [Map<String, dynamic>? medicineData]) {
    switch (timing.toLowerCase()) {
      case 'early morning':
        return '06:00 AM';
      case 'morning':
        return '08:00 AM';
      case 'afternoon':
        return '02:00 PM';
      case 'night':
      case 'evening':
        return '08:00 PM';
      case 'midnight':
        return '12:00 AM';
      case 'before sleep':
        return '10:00 PM';
      case 'early morning & morning':
        return '06:00 AM, 08:00 AM';
      case 'early morning & night':
        return '06:00 AM, 08:00 PM';
      case 'morning & afternoon':
        return '08:00 AM, 02:00 PM';
      case 'morning & night':
        return '08:00 AM, 08:00 PM';
      case 'afternoon & night':
        return '02:00 PM, 08:00 PM';
      case 'morning & afternoon & night':
        return '08:00 AM, 02:00 PM, 08:00 PM';
      case 'three times daily':
        return '08:00 AM, 02:00 PM, 08:00 PM';
      case 'evening & night':
        return '06:00 PM, 10:00 PM';
      default:
        if (timing.contains(',')) {
          return timing.trim();
        }
        return medicineData?['selectedTime']?.toString().trim() ?? '08:00 AM';
    }
  }

  static String mapTimingFromPrescription(String timing) {
    final lowerTiming = timing.toLowerCase();
    
    // Handle numerical patterns first (e.g., 1-0-1)
    if (RegExp(r'\d+-\d+-\d+').hasMatch(lowerTiming)) {
      final parts = lowerTiming.split('-');
      if (parts.length == 3) {
        final morning = parts[0] == '1';
        final afternoon = parts[1] == '1';
        final night = parts[2] == '1';
        
        if (morning && afternoon && night) return 'Morning & Afternoon & Night';
        if (morning && afternoon) return 'Morning & Afternoon';
        if (morning && night) return 'Morning & Night';
        if (afternoon && night) return 'Afternoon & Night';
        if (morning) return 'Morning';
        if (afternoon) return 'Afternoon';
        if (night) return 'Night';
      }
    }

    // Handle text-based patterns
    if (lowerTiming.contains('morning') && lowerTiming.contains('afternoon') && lowerTiming.contains('night')) {
      return 'Morning & Afternoon & Night';
    } else if (lowerTiming.contains('morning') && lowerTiming.contains('night')) {
      return 'Morning & Night';
    } else if (lowerTiming.contains('morning') && lowerTiming.contains('afternoon')) {
      return 'Morning & Afternoon';
    } else if (lowerTiming.contains('afternoon') && lowerTiming.contains('night')) {
      return 'Afternoon & Night';
    } else if (lowerTiming.contains('morning')) {
      return 'Morning';
    } else if (lowerTiming.contains('afternoon')) {
      return 'Afternoon';
    } else if (lowerTiming.contains('night') || lowerTiming.contains('evening')) {
      return 'Night';
    }
    
    return 'Morning'; // default timing
  }

  static String mapFrequencyFromPrescription(String timing) {
    final lowerTiming = timing.toLowerCase();
    
    // Handle numerical patterns (e.g., 1-1-1 or 1-0-1)
    if (RegExp(r'\d+-\d+-\d+').hasMatch(lowerTiming)) {
      final parts = lowerTiming.split('-');
      if (parts.length == 3) {
        final doseCount = parts.where((p) => p == '1').length;
        switch (doseCount) {
          case 1: return 'Once Daily';
          case 2: return 'Twice Daily';
          case 3: return 'Three Times Daily';
          case 4: return 'Four Times Daily';
        }
      }
    }

    // Handle common prescription abbreviations
    if (lowerTiming.contains('qid')) return 'Four Times Daily';
    if (lowerTiming.contains('tid') || lowerTiming.contains('tds')) return 'Three Times Daily';
    if (lowerTiming.contains('bd') || lowerTiming.contains('bid')) return 'Twice Daily';
    if (lowerTiming.contains('od')) return 'Once Daily';

    // Handle text descriptions
    if (lowerTiming.contains('four times')) return 'Four Times Daily';
    if (lowerTiming.contains('three times') || 
        lowerTiming.contains('thrice') || 
        lowerTiming.contains('morning & afternoon & night') ||
        (lowerTiming.contains('morning') && lowerTiming.contains('afternoon') && lowerTiming.contains('night'))) {
      return 'Three Times Daily';
    }
    if (lowerTiming.contains('twice') || lowerTiming.contains('two times')) return 'Twice Daily';
    if (lowerTiming.contains('once')) return 'Once Daily';

    // Count timing occurrences
    final timingParts = lowerTiming.split('&').length;
    switch (timingParts) {
      case 2: return 'Twice Daily';
      case 3: return 'Three Times Daily';
      case 4: return 'Four Times Daily';
      default: return 'Once Daily';
    }
  }

  static String mapFoodInstructionsFromPrescription(String instructions) {
    final lowerInstructions = instructions.toLowerCase();
    if (lowerInstructions.contains('before')) return 'Before Food';
    if (lowerInstructions.contains('after')) return 'After Food';
    if (lowerInstructions.contains('with')) return 'With Food';
    if (lowerInstructions.contains('empty')) return 'Empty Stomach';
    return 'After Food';
  }
  
  // Helper methods for caretaker screen
  
  // Get valid timing options for dropdown
  static List<String> getValidTimingOptions() {
    return [
      'Morning', 
      'Afternoon', 
      'Evening', 
      'Night', 
      'Morning & Afternoon', 
      'Morning & Night', 
      'Afternoon & Night', 
      'Morning & Afternoon & Night'
    ];
  }
  
  // Get valid frequency options for dropdown
  static List<String> getValidFrequencyOptions() {
    return [
      'Once Daily', 
      'Twice Daily', 
      'Three Times Daily', 
      'Four Times Daily', 
      'Every 6 Hours', 
      'Every 8 Hours', 
      'Every 12 Hours', 
      'Custom Interval'
    ];
  }

  // Get custom interval options for more granular control
  static List<String> getCustomIntervalOptions() {
    return [
      'Every 30 Minutes',
      'Every 1 Hour',
      'Every 1.5 Hours',
      'Every 2 Hours',
      'Every 3 Hours',
      'Every 4 Hours',
      'Every 6 Hours',
      'Every 8 Hours',
      'Every 12 Hours',
      'Every 18 Hours',
      'Every 24 Hours',
      'Every 36 Hours',
      'Every 48 Hours',
      'Every 72 Hours',
      'Every 96 Hours',
      'Every 1 Week',
      'Every 2 Weeks',
      'Every 1 Month',
    ];
  }

  // Parse frequency string to get interval in hours
  static int? parseFrequencyToHours(String frequency) {
    // Handle "Every X Hours" format
    final hourMatch = RegExp(r'every (\d+(?:\.\d+)?) hours?', caseSensitive: false).firstMatch(frequency);
    if (hourMatch != null) {
      final hours = double.tryParse(hourMatch.group(1) ?? '');
      return hours?.round();
    }
    
    // Handle "Every X Minutes" format
    final minuteMatch = RegExp(r'every (\d+) minutes?', caseSensitive: false).firstMatch(frequency);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1) ?? '');
      return minutes != null ? (minutes / 60).round() : null;
    }
    
    // Handle "Every X Weeks" format
    final weekMatch = RegExp(r'every (\d+) weeks?', caseSensitive: false).firstMatch(frequency);
    if (weekMatch != null) {
      final weeks = int.tryParse(weekMatch.group(1) ?? '');
      return weeks != null ? weeks * 24 * 7 : null;
    }
    
    // Handle "Every X Month" format
    final monthMatch = RegExp(r'every (\d+) months?', caseSensitive: false).firstMatch(frequency);
    if (monthMatch != null) {
      final months = int.tryParse(monthMatch.group(1) ?? '');
      return months != null ? months * 24 * 30 : null; // Approximate
    }
    
    // Handle standard frequency patterns
    switch (frequency.toLowerCase()) {
      case 'once daily':
        return 24;
      case 'twice daily':
        return 12;
      case 'three times daily':
        return 8;
      case 'four times daily':
        return 6;
      default:
        return null;
    }
  }

  // Generate times based on frequency
  static List<TimeOfDay> generateTimesFromFrequency(String frequency, {TimeOfDay? startTime}) {
    final intervalHours = parseFrequencyToHours(frequency);
    if (intervalHours == null) {
      // For unknown frequency, return a default time
      return [startTime ?? TimeOfDay(hour: 8, minute: 0)];
    }
    
    if (intervalHours >= 24) {
      // For daily or longer intervals, return single time
      return [startTime ?? TimeOfDay(hour: 8, minute: 0)];
    }
    
    // For sub-daily intervals, generate multiple times
    final times = <TimeOfDay>[];
    final start = startTime ?? TimeOfDay(hour: 8, minute: 0);
    final startMinutes = start.hour * 60 + start.minute;
    
    // Generate times for a 24-hour period
    for (int i = 0; i < 24; i += intervalHours) {
      final totalMinutes = startMinutes + (i * 60);
      final hour = (totalMinutes ~/ 60) % 24;
      final minute = totalMinutes % 60;
      times.add(TimeOfDay(hour: hour, minute: minute));
    }
    
    return times;
  }

  // Format frequency for display
  static String formatFrequencyForDisplay(String frequency) {
    final intervalHours = parseFrequencyToHours(frequency);
    if (intervalHours == null) return frequency;
    
    if (intervalHours >= 24 * 7) {
      final weeks = intervalHours ~/ (24 * 7);
      return weeks == 1 ? 'Every 1 Week' : 'Every $weeks Weeks';
    } else if (intervalHours >= 24) {
      final days = intervalHours ~/ 24;
      return days == 1 ? 'Every 1 Day' : 'Every $days Days';
    } else if (intervalHours >= 1) {
      return intervalHours == 1 ? 'Every 1 Hour' : 'Every $intervalHours Hours';
    } else {
      final minutes = (intervalHours * 60).round();
      return 'Every $minutes Minutes';
    }
  }
  
  // Get safe timing value for dropdown (ensures it's a valid option)
  static String getSafeTimingValue(Map<String, dynamic> medicineData) {
    final validOptions = getValidTimingOptions();
    
    // First try to use the timing field
    if (medicineData['timing'] != null && validOptions.contains(medicineData['timing'])) {
      return medicineData['timing'];
    }
    
    // If timing is not valid, try to infer from time
    if (medicineData['time'] != null) {
      final timeStr = medicineData['time'].toString();
      
      // Try to match common time patterns
      if (timeStr.contains('8:00 AM') || timeStr.contains('08:00 AM')) {
        return 'Morning';
      } else if (timeStr.contains('2:00 PM') || timeStr.contains('14:00')) {
        return 'Afternoon';
      } else if (timeStr.contains('8:00 PM') || timeStr.contains('20:00')) {
        return 'Night';
      }
      
      // Check for multiple times
      if (timeStr.contains(',')) {
        final times = timeStr.split(',').map((t) => t.trim()).toList();
        if (times.length == 2) {
          if ((times[0].contains('8:00 AM') || times[0].contains('08:00 AM')) && 
              (times[1].contains('2:00 PM') || times[1].contains('14:00'))) {
            return 'Morning & Afternoon';
          }
          if ((times[0].contains('8:00 AM') || times[0].contains('08:00 AM')) && 
              (times[1].contains('8:00 PM') || times[1].contains('20:00'))) {
            return 'Morning & Night';
          }
          if ((times[0].contains('2:00 PM') || times[0].contains('14:00')) && 
              (times[1].contains('8:00 PM') || times[1].contains('20:00'))) {
            return 'Afternoon & Night';
          }
        } else if (times.length == 3) {
          return 'Morning & Afternoon & Night';
        }
      }
    }
    
    // Default to Morning as a safe value
    return 'Morning';
  }
  
  // Get safe frequency value for dropdown
  static String getSafeFrequencyValue(Map<String, dynamic> medicineData) {
    final validOptions = getValidFrequencyOptions();
    
    if (medicineData['frequency'] != null && validOptions.contains(medicineData['frequency'])) {
      return medicineData['frequency'];
    }
    
    // Default based on timing
    if (medicineData['timing'] != null) {
      return mapFrequencyFromPrescription(medicineData['timing']);
    }
    
    return 'Once Daily';
  }

  // New methods for date range selection and duration calculation
  
  /// Calculate duration in days between two dates
  static int calculateDurationDays(DateTime startDate, DateTime endDate) {
    return endDate.difference(startDate).inDays + 1; // +1 to include both start and end dates
  }
  
  /// Format date range for display
  static String formatDateRange(DateTime startDate, DateTime endDate) {
    final startStr = _formatDate(startDate);
    final endStr = _formatDate(endDate);
    final days = calculateDurationDays(startDate, endDate);
    
    if (days == 1) {
      return '1 day ($startStr)';
    } else if (days < 7) {
      return '$days days ($startStr - $endStr)';
    } else if (days < 30) {
      final weeks = (days / 7).round();
      return '$weeks weeks ($startStr - $endStr)';
    } else if (days < 365) {
      final months = (days / 30).round();
      return '$months months ($startStr - $endStr)';
    } else {
      final years = (days / 365).round();
      return '$years years ($startStr - $endStr)';
    }
  }
  
  /// Convert date range to duration string for LLM parsing
  static String dateRangeToDurationString(DateTime startDate, DateTime endDate) {
    final days = calculateDurationDays(startDate, endDate);
    return '$days days';
  }
  
  /// Parse duration string to check if it's a valid date range format
  static bool isValidDateRangeFormat(String duration) {
    // Check if it contains date range indicators
    return duration.contains(' - ') || 
           duration.contains(' to ') || 
           duration.contains('from ') ||
           duration.contains('until ') ||
           duration.contains('till ');
  }
  
  /// Extract date range from duration string if it's in date range format
  static Map<String, DateTime>? parseDateRangeFromString(String duration) {
    // This would need to be implemented based on your specific date range format
    // For now, return null to indicate it's not a date range format
    return null;
  }
  
  /// Helper method to format date consistently
  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
  
  /// Get today's date as DateTime
  static DateTime getToday() {
    return DateTime.now();
  }
  
  /// Get tomorrow's date as DateTime
  static DateTime getTomorrow() {
    return DateTime.now().add(Duration(days: 1));
  }
  
  /// Get a date that's a specific number of days from today
  static DateTime getDateFromToday(int days) {
    return DateTime.now().add(Duration(days: days));
  }
  
  /// Check if a date is in the past
  static bool isDateInPast(DateTime date) {
    final today = DateTime.now();
    return date.isBefore(DateTime(today.year, today.month, today.day));
  }
  
  /// Check if a date is today
  static bool isDateToday(DateTime date) {
    final today = DateTime.now();
    return date.year == today.year && 
           date.month == today.month && 
           date.day == today.day;
  }

  // Custom Frequency Input Widget
  static Widget buildFrequencyInput({
    required String currentFrequency,
    required Function(String) onFrequencyChanged,
    required BuildContext context,
  }) {
    return FrequencyInputWidget(
      currentFrequency: currentFrequency,
      onFrequencyChanged: onFrequencyChanged,
    );
  }
}

class FrequencyInputWidget extends StatefulWidget {
  final String currentFrequency;
  final Function(String) onFrequencyChanged;

  const FrequencyInputWidget({
    Key? key,
    required this.currentFrequency,
    required this.onFrequencyChanged,
  }) : super(key: key);

  @override
  _FrequencyInputWidgetState createState() => _FrequencyInputWidgetState();
}

class _FrequencyInputWidgetState extends State<FrequencyInputWidget> {
  String _selectedFrequency = 'Once Daily';
  bool _showCustomOptions = false;

  @override
  void initState() {
    super.initState();
    _selectedFrequency = widget.currentFrequency;
    _showCustomOptions = widget.currentFrequency == 'Custom Interval';
  }

  @override
  void didUpdateWidget(FrequencyInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentFrequency != widget.currentFrequency) {
      setState(() {
        _selectedFrequency = widget.currentFrequency;
        _showCustomOptions = widget.currentFrequency == 'Custom Interval';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the dropdown value - if it's a custom interval, show "Custom Interval"
    String dropdownValue = _selectedFrequency;
    if (!TimingUtils.getValidFrequencyOptions().contains(_selectedFrequency)) {
      dropdownValue = 'Custom Interval';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Frequency (How Often)',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        SizedBox(height: 8),
        
        // Main frequency dropdown
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: dropdownValue,
              isExpanded: true,
              items: TimingUtils.getValidFrequencyOptions()
                  .map((frequency) => DropdownMenuItem(
                        value: frequency,
                        child: Text(frequency),
                      ))
                  .toList(),
              onChanged: (value) {
                setState(() {
                  if (value == 'Custom Interval') {
                    _showCustomOptions = true;
                    _selectedFrequency = 'Custom Interval';
                  } else {
                    _showCustomOptions = false;
                    _selectedFrequency = value!;
                    widget.onFrequencyChanged(value);
                  }
                });
              },
            ),
          ),
        ),
        
        // Custom interval options
        if (_showCustomOptions) ...[
          SizedBox(height: 12),
          Text(
            'Select Custom Interval',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          SizedBox(height: 8),
          
          // Quick interval buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQuickIntervalButton('Every 1 Hour'),
              _buildQuickIntervalButton('Every 2 Hours'),
              _buildQuickIntervalButton('Every 3 Hours'),
              _buildQuickIntervalButton('Every 4 Hours'),
              _buildQuickIntervalButton('Every 6 Hours'),
              _buildQuickIntervalButton('Every 8 Hours'),
              _buildQuickIntervalButton('Every 12 Hours'),
              _buildQuickIntervalButton('Every 24 Hours'),
              _buildQuickIntervalButton('Every 36 Hours'),
              _buildQuickIntervalButton('Every 48 Hours'),
              _buildQuickIntervalButton('Every 72 Hours'),
            ],
          ),
        ],
      ],
    );
  }

     Widget _buildQuickIntervalButton(String interval) {
     return InkWell(
       onTap: () {
         setState(() {
           _selectedFrequency = interval;
           _showCustomOptions = false;
         });
         widget.onFrequencyChanged(interval);
       },
       child: Container(
         padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
         decoration: BoxDecoration(
           color: Colors.white,
           borderRadius: BorderRadius.circular(16),
           border: Border.all(color: Colors.grey.shade300),
         ),
         child: Text(
           interval,
           style: TextStyle(
             fontSize: 12,
             color: Colors.grey.shade700,
             fontWeight: FontWeight.w500,
           ),
         ),
       ),
     );
   }
}
