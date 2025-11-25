import 'package:cloud_firestore/cloud_firestore.dart';

class DurationHelper {
  // Comprehensive duration keywords with variations
  static const Map<String, int> durationKeywords = {
    // Days
    'day': 1, 'days': 1, 'd': 1, 'ds': 1, 'dy': 1, 'dys': 1,
    'daily': 1, 'dia': 1, 'dias': 1,
    
    // Weeks  
    'week': 7, 'weeks': 7, 'w': 7, 'ws': 7, 'wk': 7, 'wks': 7,
    'weekly': 7, 'semana': 7, 'semanas': 7,
    
    // Months
    'month': 30, 'months': 30, 'm': 30, 'ms': 30, 'mo': 30, 'mos': 30,
    'monthly': 30, 'mes': 30, 'meses': 30, 'mth': 30, 'mths': 30,
    
    // Years
    'year': 365, 'years': 365, 'y': 365, 'ys': 365, 'yr': 365, 'yrs': 365,
    'yearly': 365, 'ano': 365, 'anos': 365,
    
    // Pills/Tablets (treat as count, but we'll handle differently)
    'pill': 1, 'pills': 1, 'p': 1, 'ps': 1, 'tablet': 1, 'tablets': 1,
    't': 1, 'ts': 1, 'tab': 1, 'tabs': 1, 'capsule': 1, 'capsules': 1,
    'cap': 1, 'caps': 1, 'dose': 1, 'doses': 1,
  };

  // Common indefinite duration phrases
  static const List<String> indefinitePhrases = [
    'till finished', 'until finished', 'till complete', 'until complete',
    'till done', 'until done', 'as needed', 'as required', 'prn',
    'continue', 'ongoing', 'indefinite', 'permanent', 'lifelong',
    'chronic', 'maintenance', 'long term', 'long-term', 'forever',
    'complete course', 'finish pack', 'finish bottle', 'use all',
    'empty', 'toda', 'completo', 'terminado'
  ];

  static int? parseDurationToDays(String duration) {
    if (duration.isEmpty) return null;
    
    duration = duration.toLowerCase().trim();
    
    // Remove common prefixes and suffixes - FIXED REGEX
    duration = duration
        .replaceAll(RegExp(r'^(for|during|take|use|continue)\s+'), '')
        .replaceAll(RegExp(r'\s+(only|total|altogether|in total)$'), '')
        .replaceAll(RegExp(r'[.,;]$'), '') // Remove trailing punctuation
        .trim();
    
    // Check for indefinite duration phrases
    for (String phrase in indefinitePhrases) {
      if (duration.contains(phrase)) {
        return null; // Indefinite duration
      }
    }
    
    // Handle special cases first
    if (_isIndefiniteDuration(duration)) {
      return null;
    }
    
    // Strategy 0: Check if it's a simple "X days" format from calendar selection
    if (RegExp(r'^\d+\s*days?$').hasMatch(duration)) {
      final match = RegExp(r'^(\d+)\s*days?$').firstMatch(duration);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    
    // Try multiple parsing strategies
    int? result;
    
    // Strategy 1: Standard number + unit format (e.g., "5 days", "2 weeks")
    result = _parseStandardFormat(duration);
    if (result != null) return result;
    
    // Strategy 2: Compact format (e.g., "5d", "2w", "10ps")
    result = _parseCompactFormat(duration);
    if (result != null) return result;
    
    // Strategy 3: Range format (e.g., "5-7 days", "2 to 3 weeks")
    result = _parseRangeFormat(duration);
    if (result != null) return result;
    
    // Strategy 4: Word numbers (e.g., "five days", "two weeks")
    result = _parseWordNumbers(duration);
    if (result != null) return result;
    
    // Strategy 5: Just numbers (assume days)
    result = _parseNumberOnly(duration);
    if (result != null) return result;
    
    // Strategy 6: Count-based durations (e.g., "30 tablets", "60 pills")
    result = _parseCountBased(duration);
    if (result != null) return result;
    
    return null;
  }
  
  static bool _isIndefiniteDuration(String duration) {
    final indefinitePatterns = [
      r'\b(till|until|up\s*to)\s+(finish|complete|done|empty)',
      r'\b(as\s+needed|prn|when\s+required)',
      r'\b(continue|ongoing|permanent|lifelong|chronic)',
      r'\b(maintenance|long[\s\-]?term)',
      r'\b(complete\s+course|finish\s+(pack|bottle|strip))',
    ];
    
    for (String pattern in indefinitePatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(duration)) {
        return true;
      }
    }
    
    return false;
  }
  
  static int? _parseStandardFormat(String duration) {
    // Matches: "5 days", "2 weeks", "1 month", etc. - FIXED REGEX
    final regex = RegExp(r'(\d+(?:\.\d+)?)\s*([a-z]+)', caseSensitive: false);
    final match = regex.firstMatch(duration);
    
    if (match != null) {
      final number = double.tryParse(match.group(1)!);
      final unit = match.group(2)!.toLowerCase();
      
      if (number != null && durationKeywords.containsKey(unit)) {
        return (number * durationKeywords[unit]!).round();
      }
    }
    
    return null;
  }
  
  static int? _parseCompactFormat(String duration) {
    // Matches: "5d", "2w", "10ps", "30t", etc. - FIXED REGEX
    final compactPatterns = [
      RegExp(r'(\d+)\s*([dwmy]s?)$', caseSensitive: false), // 5d, 2ws, 3m, etc.
      RegExp(r'(\d+)\s*([pt]s?)$', caseSensitive: false),   // 30p, 60ps, 20t, etc.
      RegExp(r'(\d+)\s*(tab|cap)s?$', caseSensitive: false), // 30tab, 60caps
    ];
    
    for (RegExp regex in compactPatterns) {
      final match = regex.firstMatch(duration);
      if (match != null) {
        final number = int.tryParse(match.group(1)!);
        final unit = match.group(2)!.toLowerCase();
        
        if (number != null) {
          // Handle special compact units
          switch (unit) {
            case 'd': case 'ds': return number;
            case 'w': case 'ws': return number * 7;
            case 'm': case 'ms': return number * 30;
            case 'y': case 'ys': return number * 365;
            case 'p': case 'ps': case 't': case 'ts':
            case 'tab': case 'tabs': case 'cap': case 'caps':
              // For pills/tablets, estimate based on typical dosing
              return _estimateDaysFromCount(number);
          }
          
          if (durationKeywords.containsKey(unit)) {
            return number * durationKeywords[unit]!;
          }
        }
      }
    }
    
    return null;
  }
  
  static int? _parseRangeFormat(String duration) {
    // Matches: "5-7 days", "2 to 3 weeks", "10-14 d" - FIXED REGEX
    final rangePatterns = [
      RegExp(r'(\d+)[\s\-to]*(\d+)\s*([a-z]+)', caseSensitive: false),
      RegExp(r'(\d+)\s*[\-to]+\s*(\d+)\s*([a-z]*)', caseSensitive: false),
    ];
    
    for (RegExp regex in rangePatterns) {
      final match = regex.firstMatch(duration);
      if (match != null) {
        final start = int.tryParse(match.group(1)!);
        final end = int.tryParse(match.group(2)!);
        final unit = match.group(3)?.toLowerCase() ?? 'days';
        
        if (start != null && end != null) {
          final avgDuration = ((start + end) / 2).round();
          final multiplier = durationKeywords[unit] ?? durationKeywords['d'] ?? 1;
          return avgDuration * multiplier;
        }
      }
    }
    
    return null;
  }
  
  static int? _parseWordNumbers(String duration) {
    // Convert word numbers to digits
    final wordNumbers = {
      'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5,
      'six': 6, 'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10,
      'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15,
      'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50, 'sixty': 60,
      'seventy': 70, 'eighty': 80, 'ninety': 90,
      'a': 1, 'an': 1, 'half': 0.5, 'quarter': 0.25,
    };
    
    String modifiedDuration = duration;
    
    // Replace word numbers with digits - FIXED REGEX
    wordNumbers.forEach((word, number) {
      modifiedDuration = modifiedDuration.replaceAll(
        RegExp(r'\b' + word + r'\b', caseSensitive: false),
        number.toString()
      );
    });
    
    // If we made changes, try parsing again
    if (modifiedDuration != duration) {
      return _parseStandardFormat(modifiedDuration) ?? 
             _parseCompactFormat(modifiedDuration);
    }
    
    return null;
  }
  
  static int? _parseNumberOnly(String duration) {
    // Extract just numbers and assume days - FIXED REGEX
    final numberMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(duration);
    if (numberMatch != null) {
      final number = double.tryParse(numberMatch.group(1)!);
      if (number != null) {
        // If it's a large number (>100), might be pill count
        if (number > 100) {
          return _estimateDaysFromCount(number.round());
        }
        // Otherwise assume days
        return number.round();
      }
    }
    
    return null;
  }
  
  static int? _parseCountBased(String duration) {
    // Handle pill/tablet counts like "30 tablets", "60 pills" - FIXED REGEX
    final countPatterns = [
      RegExp(r'(\d+)\s*(tablet|pill|capsule|cap|dose)s?', caseSensitive: false),
      RegExp(r'(\d+)\s*(tab|cap|dose)s?', caseSensitive: false),
    ];
    
    for (RegExp regex in countPatterns) {
      final match = regex.firstMatch(duration);
      if (match != null) {
        final count = int.tryParse(match.group(1)!);
        if (count != null) {
          return _estimateDaysFromCount(count);
        }
      }
    }
    
    return null;
  }
  
  static int _estimateDaysFromCount(int count) {
    // Estimate days based on pill count
    // Assume typical dosing patterns
    if (count <= 7) return count; // Daily for a week
    if (count <= 14) return count ~/ 2; // Twice daily
    if (count <= 30) return count; // Once daily for a month
    if (count <= 60) return count ~/ 2; // Twice daily for a month
    if (count <= 90) return count ~/ 3; // Three times daily for a month
    
    // For larger counts, assume once daily
    return count;
  }
  
  static bool isDurationExpired(String duration, dynamic createdAtValue) {
    final durationDays = parseDurationToDays(duration);
    if (durationDays == null) return false; // Indefinite duration
    
    try {
      DateTime startDate;
      
      // Handle both Timestamp and String types
      if (createdAtValue is Timestamp) {
        startDate = createdAtValue.toDate();
      } else if (createdAtValue is String) {
        startDate = DateTime.parse(createdAtValue);
      } else {
        return false; // Unknown type
      }
      
      final endDate = startDate.add(Duration(days: durationDays));
      return DateTime.now().isAfter(endDate);
    } catch (e) {
      print('Error parsing created date: $e');
      return false;
    }
  }
  
  static String formatDurationDisplay(String duration) {
    final durationDays = parseDurationToDays(duration);
    if (durationDays == null) return duration; // Return original for indefinite
    
    if (durationDays == 1) return "1 day";
    if (durationDays < 7) return "$durationDays days";
    if (durationDays == 7) return "1 week";
    if (durationDays < 30) {
      final weeks = (durationDays / 7).round();
      return weeks == 1 ? "1 week" : "$weeks weeks";
    }
    if (durationDays < 365) {
      final months = (durationDays / 30).round();
      return months == 1 ? "1 month" : "$months months";
    }
    final years = (durationDays / 365).round();
    return years == 1 ? "1 year" : "$years years";
  }
  
  static int? getRemainingDays(String duration, dynamic createdAtValue) {
    final durationDays = parseDurationToDays(duration);
    if (durationDays == null) return null; // Indefinite
    
    try {
      DateTime startDate;
      
      // Handle both Timestamp and String types
      if (createdAtValue is Timestamp) {
        startDate = createdAtValue.toDate();
      } else if (createdAtValue is String) {
        startDate = DateTime.parse(createdAtValue);
      } else {
        return null; // Unknown type
      }
      
      final endDate = startDate.add(Duration(days: durationDays));
      final remaining = endDate.difference(DateTime.now()).inDays;
      return remaining > 0 ? remaining : 0;
    } catch (e) {
      print('Error parsing created date: $e');
      return null;
    }
  }
  
  // Helper method to normalize duration for storage
  static String normalizeDuration(String rawDuration) {
    final durationDays = parseDurationToDays(rawDuration);
    if (durationDays == null) {
      // For indefinite durations, return a standardized phrase
      return "until finished";
    }
    
    // Return a standardized format
    return formatDurationDisplay(rawDuration);
  }
  
  /// Check if a duration string is from calendar selection
  static bool isFromCalendarSelection(String duration) {
    return RegExp(r'^\d+\s*days?$').hasMatch(duration.trim());
  }
  
  /// Extract the number of days from a calendar selection duration
  static int? extractDaysFromCalendarSelection(String duration) {
    final match = RegExp(r'^(\d+)\s*days?$').firstMatch(duration.trim());
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}