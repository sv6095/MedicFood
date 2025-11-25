import 'package:http/http.dart' as http;
import 'dart:convert';

class DrugApiService {
  static const String rxNormBaseUrl = 'https://rxnav.nlm.nih.gov/REST';
  static const String openFdaBaseUrl = 'https://api.fda.gov/drug/label.json';

  // Enhanced caching with TTL
  static final Map<String, Map<String, dynamic>> _validationCache = {};
  static final Map<String, String> _rxcuiCache = {};
  static final Map<String, Map<String, dynamic>> _drugDetailsCache = {};
  static final Set<String> _validDrugNames = {};
  static final Set<String> _invalidDrugNames = {};
  
  // Cache TTL (5 minutes)
  static const int _cacheTTL = 300000; // milliseconds
  static final Map<String, int> _cacheTimestamps = {};
  
  // Medicine type mapping for better matching
  static const Map<String, List<String>> medicineTypeMap = {
    'tablet': ['tab', 'tabs', 'tablet', 'tablets', 'pill', 'pills', 'cap', 'capsule'],
    'capsule': ['cap', 'caps', 'capsule', 'capsules', 'gel', 'gelcap'],
    'syrup': ['syrup', 'solution', 'susp', 'suspension', 'liquid', 'elixir'],
    'injection': ['inj', 'injection', 'injectable', 'vial', 'amp', 'ampoule'],
    'cream': ['cream', 'ointment', 'lotion', 'gel', 'topical'],
    'spray': ['spray', 'nasal', 'inhaler', 'aerosol', 'mist'],
    'drops': ['drops', 'eye drops', 'ear drops', 'ophthalmic', 'otic'],
    'powder': ['powder', 'granules', 'sachet', 'for reconstitution'],
    'patch': ['patch', 'transdermal', 'plaster'],
  };

  // Pre-built reverse lookup for faster type matching
  static final Map<String, String> _formToCategory = _buildFormToCategoryMap();

  static Map<String, String> _buildFormToCategoryMap() {
    final map = <String, String>{};
    for (final entry in medicineTypeMap.entries) {
      for (final form in entry.value) {
        map[form] = entry.key;
      }
    }
    return map;
  }

  Future<Map<String, dynamic>> validateDrug(String drugName, {String? medicineType}) async {
    final lowerName = drugName.toLowerCase().trim();
    
    // Generate cache key that includes medicine type if provided
    final cacheKey = medicineType != null ? "$lowerName:${medicineType.toLowerCase()}" : lowerName;
    
    // Check cache first with TTL
    if (_isCacheValid(cacheKey) && _validationCache.containsKey(cacheKey)) {
      return _validationCache[cacheKey]!;
    }

    try {
      // Quick validation check first
      bool isValid = await _isValidDrugNameFast(lowerName);
      
      if (isValid) {
        // Get drug details and RXCUI in parallel
        final results = await Future.wait([
          _getDrugDetailsFast(lowerName),
          _getRxcuiFast(lowerName),
        ]);
        
        final details = results[0] as Map<String, dynamic>;
        final rxcui = results[1] as String;
        
        // If medicine type was provided, validate the type
        bool typeMatches = true;
        if (medicineType != null && details['form'] != null) {
          typeMatches = _doTypesMatchFast(details['form'].toString(), medicineType);
        }
        
        // If type doesn't match, try to find a better match with correct type
        if (!typeMatches && medicineType != null) {
          // Try to find medication with matching type (with timeout)
          final typeMatchedDrug = await _findDrugWithMatchingTypeFast(lowerName, medicineType)
              .timeout(Duration(seconds: 3), onTimeout: () => '');
          
          if (typeMatchedDrug.isNotEmpty) {
            // We found a better match that has the right type
            final result = {
              'isValid': true,
              'originalName': drugName,
              'correctedName': typeMatchedDrug,
              'wasCorrected': typeMatchedDrug.toLowerCase() != lowerName,
              'confidence': 0.9,
              'correctionMethod': 'type_matching',
              'details': await _getDrugDetailsFast(typeMatchedDrug),
              'rxcui': await _getRxcuiFast(typeMatchedDrug),
              'alternativeSuggestions': <String>[],
              'requestedType': medicineType,
              'matchedType': true,
            };
            _setCache(cacheKey, result);
            return result;
          }
        }
        
        final result = {
          'isValid': true,
          'originalName': drugName,
          'correctedName': drugName,
          'wasCorrected': false,
          'confidence': typeMatches ? 1.0 : 0.8,
          'correctionMethod': 'exact_match',
          'details': details,
          'rxcui': rxcui,
          'alternativeSuggestions': <String>[],
          'requestedType': medicineType,
          'matchedType': typeMatches,
        };
        _setCache(cacheKey, result);
        return result;
      }

      // Try corrections if exact match fails (limited to 3 candidates for speed)
      final candidates = _generateCorrectionCandidates(lowerName).take(3).toList();
      
      // If medicine type provided, prioritize candidates that match the type
      if (medicineType != null) {
        final typePrioritizedCandidates = await _prioritizeCandidatesByTypeFast(candidates, medicineType);
        if (typePrioritizedCandidates.isNotEmpty) {
          candidates.clear();
          candidates.addAll(typePrioritizedCandidates.take(3));
        }
      }
      
      // Check candidates in parallel with timeout
      final candidateResults = await _checkCandidatesInParallel(candidates, lowerName, drugName, medicineType);
      if (candidateResults != null) {
        _setCache(cacheKey, candidateResults);
        return candidateResults;
      }

      // Try RxNorm approximate match as fallback (with shorter timeout)
      final approxMatch = await _tryRxNormApproximateMatchFast(lowerName, medicineType: medicineType)
          .timeout(Duration(seconds: 3), onTimeout: () => '');
      
      if (approxMatch.isNotEmpty && approxMatch != lowerName) {
        final details = await _getDrugDetailsFast(approxMatch);
        
        // Check if the form matches the requested type
        bool typeMatches = true;
        if (medicineType != null && details['form'] != null) {
          typeMatches = _doTypesMatchFast(details['form'].toString(), medicineType);
        }
        
        final result = {
          'isValid': true,
          'originalName': drugName,
          'correctedName': approxMatch,
          'wasCorrected': true,
          'confidence': 0.8 * (typeMatches ? 1.0 : 0.8),
          'correctionMethod': 'approximate_match',
          'details': details,
          'rxcui': await _getRxcuiFast(approxMatch),
          'alternativeSuggestions': <String>[approxMatch],
          'requestedType': medicineType, 
          'matchedType': typeMatches,
        };
        _setCache(cacheKey, result);
        return result;
      }

      // Not found
      final result = {
        'isValid': false,
        'originalName': drugName,
        'correctedName': drugName,
        'wasCorrected': false,
        'confidence': 0.1,
        'correctionMethod': 'not_found',
        'details': {},
        'rxcui': '',
        'alternativeSuggestions': <String>[],
        'requestedType': medicineType,
        'matchedType': false,
      };
      _setCache(cacheKey, result);
      return result;

    } catch (e) {
      print('Validation error for $drugName: $e');
      return {
        'isValid': false,
        'originalName': drugName,
        'correctedName': drugName,
        'wasCorrected': false,
        'confidence': 0.0,
        'correctionMethod': 'error',
        'details': {},
        'rxcui': '',
        'alternativeSuggestions': <String>[],
        'requestedType': medicineType,
        'matchedType': false,
      };
    }
  }

  // Cache management methods
  bool _isCacheValid(String key) {
    final timestamp = _cacheTimestamps[key];
    if (timestamp == null) return false;
    return DateTime.now().millisecondsSinceEpoch - timestamp < _cacheTTL;
  }

  void _setCache(String key, Map<String, dynamic> value) {
    _validationCache[key] = value;
    _cacheTimestamps[key] = DateTime.now().millisecondsSinceEpoch;
  }

  // Clear all caches
  static void clearCache() {
    _validationCache.clear();
    _rxcuiCache.clear();
    _drugDetailsCache.clear();
    _validDrugNames.clear();
    _invalidDrugNames.clear();
    _cacheTimestamps.clear();
  }

  // Clear expired cache entries
  static void clearExpiredCache() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now - entry.value > _cacheTTL)
        .map((entry) => entry.key)
        .toList();
    
    for (final key in expiredKeys) {
      _validationCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  // Get cache statistics
  static Map<String, int> getCacheStats() {
    return {
      'validationCache': _validationCache.length,
      'rxcuiCache': _rxcuiCache.length,
      'drugDetailsCache': _drugDetailsCache.length,
      'validDrugNames': _validDrugNames.length,
      'invalidDrugNames': _invalidDrugNames.length,
    };
  }

  // Fast type matching using pre-built lookup
  bool _doTypesMatchFast(String form1, String form2) {
    final normalizedForm1 = form1.toLowerCase();
    final normalizedForm2 = form2.toLowerCase();
    
    // Direct match
    if (normalizedForm1 == normalizedForm2) return true;
    
    // Use pre-built lookup for faster matching
    final category1 = _formToCategory[normalizedForm1];
    final category2 = _formToCategory[normalizedForm2];
    
    return category1 != null && category1 == category2;
  }

  // Fast validation with better caching
  Future<bool> _isValidDrugNameFast(String drugName) async {
    if (_validDrugNames.contains(drugName)) {
      return true;
    }
    
    if (_invalidDrugNames.contains(drugName)) {
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('$rxNormBaseUrl/rxcui.json?name=${Uri.encodeComponent(drugName)}'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        bool isValid = data['idGroup']['rxnormId'] != null &&
            (data['idGroup']['rxnormId'] as List).isNotEmpty;
        
        if (isValid) {
          _validDrugNames.add(drugName);
        } else {
          _invalidDrugNames.add(drugName);
        }
        return isValid;
      }
    } catch (e) {
      print('Validation failed for $drugName: $e');
    }
    
    _invalidDrugNames.add(drugName);
    return false;
  }

  // Fast RXCUI retrieval with caching
  Future<String> _getRxcuiFast(String drugName) async {
    if (_rxcuiCache.containsKey(drugName)) {
      return _rxcuiCache[drugName]!;
    }

    try {
      final response = await http.get(
        Uri.parse('$rxNormBaseUrl/rxcui.json?name=${Uri.encodeComponent(drugName)}'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final rxnormIds = data['idGroup']['rxnormId'] as List?;
        if (rxnormIds != null && rxnormIds.isNotEmpty) {
          final rxcui = rxnormIds.first.toString();
          _rxcuiCache[drugName] = rxcui;
          return rxcui;
        }
      }
    } catch (e) {
      print('Failed to get RXCUI for $drugName: $e');
    }
    
    _rxcuiCache[drugName] = '';
    return '';
  }

  // Fast drug details retrieval with caching
  Future<Map<String, dynamic>> _getDrugDetailsFast(String drugName) async {
    if (_drugDetailsCache.containsKey(drugName)) {
      return _drugDetailsCache[drugName]!;
    }

    try {
      final rxcui = await _getRxcuiFast(drugName);
      if (rxcui.isNotEmpty) {
        final response = await http.get(
          Uri.parse('$rxNormBaseUrl/rxcui/$rxcui/properties.json'),
        ).timeout(Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final properties = data['properties'];
          if (properties != null) {
            final details = {
              'name': properties['name'] ?? drugName,
              'synonym': properties['synonym'] ?? '',
              'tty': properties['tty'] ?? '',
              'form': _extractForm(properties['tty'] ?? ''),
            };
            _drugDetailsCache[drugName] = details;
            return details;
          }
        }
      }
    } catch (e) {
      print('Failed to get drug details for $drugName: $e');
    }
    
    final defaultDetails = {'name': drugName, 'form': 'tablet'};
    _drugDetailsCache[drugName] = defaultDetails;
    return defaultDetails;
  }

  // Fast type matching with reduced API calls
  Future<String> _findDrugWithMatchingTypeFast(String drugName, String desiredType) async {
    try {
      final response = await http.get(
        Uri.parse('$rxNormBaseUrl/approximateTerm.json?term=${Uri.encodeComponent(drugName)}&maxEntries=5'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['approximateGroup']['candidate'] != null) {
          final candidates = data['approximateGroup']['candidate'] as List;
          
          // Check each candidate for matching type (limited to first 3)
          for (final candidate in candidates.take(3)) {
            final candidateName = candidate['name']?.toString().toLowerCase() ?? '';
            if (candidateName.isNotEmpty) {
              final details = await _getDrugDetailsFast(candidateName);
              final form = details['form']?.toString().toLowerCase() ?? '';
              
              if (_doTypesMatchFast(form, desiredType)) {
                return candidate['name']?.toString() ?? '';
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error finding drug with matching type: $e');
    }
    
    return '';
  }

  // Fast candidate prioritization with reduced API calls
  Future<List<String>> _prioritizeCandidatesByTypeFast(List<String> candidates, String desiredType) async {
    final typeScoredCandidates = <String, double>{};
    final result = <String>[];
    
    // Process candidates in parallel with timeout
    final futures = candidates.map((candidate) async {
      try {
        final details = await _getDrugDetailsFast(candidate);
        final form = details['form']?.toString().toLowerCase() ?? '';
        final typeMatches = _doTypesMatchFast(form, desiredType);
        
        return {
          'candidate': candidate,
          'score': typeMatches ? 3.0 : 1.0,
        };
      } catch (e) {
        return {
          'candidate': candidate,
          'score': 0.5,
        };
      }
    });
    
    final results = await Future.wait(futures);
    
    for (final result in results) {
      final resultMap = result as Map<String, dynamic>;
      typeScoredCandidates[resultMap['candidate']] = resultMap['score'];
    }
    
    // Sort candidates by score (descending)
    final sortedCandidates = typeScoredCandidates.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    result.addAll(sortedCandidates.map((e) => e.key));
    return result;
  }

  // Check candidates in parallel for better performance
  Future<Map<String, dynamic>?> _checkCandidatesInParallel(
    List<String> candidates, 
    String lowerName, 
    String drugName, 
    String? medicineType
  ) async {
    final futures = candidates.map((candidate) async {
      try {
        final isValid = await _isValidDrugNameFast(candidate);
        if (isValid) {
          final details = await _getDrugDetailsFast(candidate);
          final rxcui = await _getRxcuiFast(candidate);
          
          bool typeMatches = true;
          if (medicineType != null && details['form'] != null) {
            typeMatches = _doTypesMatchFast(details['form'].toString(), medicineType);
          }
          
          return {
            'candidate': candidate,
            'details': details,
            'rxcui': rxcui,
            'typeMatches': typeMatches,
            'confidence': _calculateConfidence(lowerName, candidate) * (typeMatches ? 1.0 : 0.8),
          };
        }
      } catch (e) {
        // Ignore errors for individual candidates
      }
      return null;
    });
    
    final results = await Future.wait(futures);
    final validResults = results.where((r) => r != null).toList();
    
    if (validResults.isNotEmpty) {
      // Return the best match
      validResults.sort((a, b) => (b as Map<String, dynamic>)['confidence'].compareTo((a as Map<String, dynamic>)['confidence']));
      final best = validResults.first! as Map<String, dynamic>;
      
      return {
        'isValid': true,
        'originalName': drugName,
        'correctedName': best['candidate'],
        'wasCorrected': true,
        'confidence': best['confidence'],
        'correctionMethod': 'spelling_correction',
        'details': best['details'],
        'rxcui': best['rxcui'],
        'alternativeSuggestions': candidates.take(3).toList(),
        'requestedType': medicineType,
        'matchedType': best['typeMatches'],
      };
    }
    
    return null;
  }

  // Fast approximate matching with reduced timeout
  Future<String> _tryRxNormApproximateMatchFast(String drugName, {String? medicineType}) async {
    try {
      final response = await http.get(
        Uri.parse('$rxNormBaseUrl/approximateTerm.json?term=${Uri.encodeComponent(drugName)}&maxEntries=3'),
      ).timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['approximateGroup']['candidate'] != null) {
          final candidates = data['approximateGroup']['candidate'] as List;
          if (candidates.isNotEmpty) {
            // If medicine type is provided, try to find a match with that type
            if (medicineType != null) {
              for (final candidate in candidates.take(2)) {
                final candidateName = candidate['name']?.toString() ?? '';
                if (candidateName.isNotEmpty) {
                  final details = await _getDrugDetailsFast(candidateName.toLowerCase());
                  final form = details['form']?.toString() ?? '';
                  
                  if (_doTypesMatchFast(form, medicineType)) {
                    return candidateName.toLowerCase();
                  }
                }
              }
            }
            
            // If no type match or no type provided, return best match
            final bestMatch = candidates.first;
            return bestMatch['name']?.toString().toLowerCase() ?? '';
          }
        }
      }
    } catch (e) {
      print('RxNorm approximate matching failed: $e');
    }
    return '';
  }

  String _extractForm(String tty) {
    // Enhanced TTY (Term Type) mapping to forms
    const Map<String, String> ttyToForm = {
      'SCD': 'tablet',
      'SBD': 'tablet',
      'SCDC': 'capsule',
      'SBDC': 'capsule',
      'SCDF': 'syrup',
      'SBDF': 'syrup',
      'SCSP': 'spray',
      'SBSP': 'spray',
      'SCINJ': 'injection',
      'SBINJ': 'injection',
      'SCCT': 'cream',
      'SBCT': 'cream',
      'SCDP': 'drops',
      'SBDP': 'drops',
      'SCPD': 'powder',
      'SBPD': 'powder',
      'SCPT': 'patch',
      'SBPT': 'patch',
      'IN': 'tablet',
      'PIN': 'tablet',
      'MIN': 'tablet',
      'BN': 'tablet',
      'TMSY': 'syrup',
      'SU': 'suppository',
      'SUSP': 'suspension',
      'ELIX': 'syrup',
      'SOL': 'solution',
      'INJ': 'injection',
      'IH': 'inhaler',
      'OIN': 'ointment',
      'GEL': 'gel',
      'LOT': 'lotion',
      'CREA': 'cream',
      'TOP': 'topical',
      'DRP': 'drops',
      'POW': 'powder',
      'GRAN': 'granules',
      'PAT': 'patch',
    };
    
    // Get the form from the TTY code
    String form = ttyToForm[tty.toUpperCase()] ?? 'tablet';
    
    // Alternative approach: check if the TTY contains specific strings
    final lowerTty = tty.toLowerCase();
    if (lowerTty.contains('cap')) return 'capsule';
    if (lowerTty.contains('tab')) return 'tablet';
    if (lowerTty.contains('inj')) return 'injection';
    if (lowerTty.contains('syr') || lowerTty.contains('sol')) return 'syrup';
    if (lowerTty.contains('cre') || lowerTty.contains('oint')) return 'cream';
    if (lowerTty.contains('spr') || lowerTty.contains('aer')) return 'spray';
    if (lowerTty.contains('drop')) return 'drops';
    if (lowerTty.contains('pow') || lowerTty.contains('gran')) return 'powder';
    if (lowerTty.contains('pat') || lowerTty.contains('tran')) return 'patch';
    
    return form;
  }

  double _calculateConfidence(String original, String corrected) {
    if (original.toLowerCase() == corrected.toLowerCase()) return 1.0;
    
    int distance = _levenshteinDistance(original.toLowerCase(), corrected.toLowerCase());
    int maxLength = [original.length, corrected.length].reduce((a, b) => a > b ? a : b);
    
    if (maxLength == 0) return 0.0;
    
    double baseConfidence = 1.0 - (distance / maxLength);
    
    // Boost confidence for medical patterns
    if (_hasCommonMedicalPatterns(corrected)) {
      baseConfidence += 0.1;
    }
    
    // Consider length similarity
    double lengthSimilarity = 1.0 - ((original.length - corrected.length).abs() / maxLength);
    baseConfidence = (baseConfidence + lengthSimilarity) / 2;
    
    return baseConfidence.clamp(0.0, 1.0);
  }

  bool _hasCommonMedicalPatterns(String drugName) {
    List<String> medicalSuffixes = [
      'ine', 'in', 'ol', 'ide', 'ate', 'ium', 'mycin', 'cillin',
      'prazole', 'statin', 'floxacin', 'zole', 'pine', 'done'
    ];
    return medicalSuffixes.any((suffix) => drugName.endsWith(suffix));
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;
    
    List<List<int>> matrix = List.generate(
      s1.length + 1,
      (i) => List.generate(s2.length + 1, (j) => 0),
    );
    
    for (int i = 0; i <= s1.length; i++) matrix[i][0] = i;
    for (int j = 0; j <= s2.length; j++) matrix[0][j] = j;
    
    for (int i = 1; i <= s1.length; i++) {
      for (int j = 1; j <= s2.length; j++) {
        int cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    return matrix[s1.length][s2.length];
  }

  // Optimized candidate generation
  List<String> _generateCorrectionCandidates(String drugName) {
    Set<String> candidates = {};

    // Token corrections
    candidates.addAll(_applyTokenCorrections(drugName));
    
    // Character substitutions
    candidates.addAll(_applyCharacterSubstitutions(drugName));
    
    // Medical pattern corrections
    candidates.addAll(_applyMedicalPatternCorrections(drugName));

    // Remove original and empty strings
    candidates.remove(drugName);
    candidates.removeWhere((c) => c.isEmpty || c.length < 2);

    // Sort by confidence and limit to top 5 for speed
    List<String> sorted = candidates.toList();
    sorted.sort((a, b) => _calculateConfidence(drugName, b).compareTo(_calculateConfidence(drugName, a)));
    
    return sorted.take(5).toList();
  }

  List<String> _applyTokenCorrections(String drugName) {
    List<String> candidates = [];
    
    // Remove numbers
    RegExp numberPattern = RegExp(r'\d+');
    if (numberPattern.hasMatch(drugName)) {
      String withoutNumbers = drugName.replaceAll(numberPattern, '').trim();
      if (withoutNumbers.isNotEmpty) {
        candidates.add(withoutNumbers);
      }
    }
    
    // Handle spaces and hyphens
    if (drugName.contains(' ')) {
      candidates.add(drugName.replaceAll(' ', ''));
      candidates.addAll(drugName.split(' '));
    }
    if (drugName.contains('-')) {
      candidates.add(drugName.replaceAll('-', ''));
      candidates.addAll(drugName.split('-'));
    }
    
    return candidates;
  }

  List<String> _applyCharacterSubstitutions(String drugName) {
    List<String> candidates = [];
    String name = drugName;
    
    Map<String, List<String>> substitutions = {
      'i': ['y', 'e'],
      'y': ['i', 'ie'],
      'c': ['k', 's', 'ck'],
      'k': ['c', 'ck'],
      's': ['c', 'z'],
      'z': ['s'],
      'f': ['ph', 'v'],
      'ph': ['f'],
      'tion': ['sion'],
      'sion': ['tion'],
      'ine': ['in'],
      'in': ['ine'],
    };
    
    substitutions.forEach((original, replacements) {
      for (String replacement in replacements) {
        if (name.contains(original)) {
          candidates.add(name.replaceAll(original, replacement));
        }
      }
    });
    
    return candidates;
  }

  List<String> _applyMedicalPatternCorrections(String drugName) {
    List<String> candidates = [];
    String name = drugName;
    
    List<Map<String, String>> medicalPatterns = [
      {'pattern': r'mycin$', 'replacement': 'micin'},
      {'pattern': r'micin$', 'replacement': 'mycin'},
      {'pattern': r'cillin$', 'replacement': 'cilllin'},
      {'pattern': r'cilllin$', 'replacement': 'cillin'},
      {'pattern': r'^pred', 'replacement': 'prednis'},
      {'pattern': r'prazole$', 'replacement': 'prazol'},
      {'pattern': r'prazol$', 'replacement': 'prazole'},
      {'pattern': r'olol$', 'replacement': 'anol'},
      {'pattern': r'anol$', 'replacement': 'olol'},
    ];
    
    for (var pattern in medicalPatterns) {
      RegExp regex = RegExp(pattern['pattern']!);
      if (regex.hasMatch(name)) {
        candidates.add(name.replaceAll(regex, pattern['replacement']!));
      }
    }
    
    return candidates;
  }

  // Additional methods for compatibility
  Future<List<Map<String, dynamic>>> validateDrugs(List<String> drugNames) async {
    return await Future.wait(drugNames.map((name) => validateDrug(name)));
  }

  // Batch validation with optimized parallel processing
  Future<List<Map<String, dynamic>>> validateDrugsBatch(List<String> drugNames, {String? medicineType}) async {
    // Group drugs by first letter for better caching and processing
    final groupedDrugs = <String, List<String>>{};
    for (final drug in drugNames) {
      final firstChar = drug.toLowerCase().isNotEmpty ? drug.toLowerCase()[0] : '#';
      groupedDrugs.putIfAbsent(firstChar, () => []).add(drug);
    }
    
    final results = <Map<String, dynamic>>[];
    
    // Process each group in parallel
    final groupFutures = groupedDrugs.entries.map((entry) async {
      final groupResults = await Future.wait(
        entry.value.map((drug) => validateDrug(drug, medicineType: medicineType))
      );
      return groupResults;
    });
    
    final groupResults = await Future.wait(groupFutures);
    
    // Flatten results
    for (final group in groupResults) {
      results.addAll(group);
    }
    
    return results;
  }

  // Fast validation for multiple drugs with shared cache
  Future<Map<String, Map<String, dynamic>>> validateDrugsWithCache(
    List<String> drugNames, 
    {String? medicineType}
  ) async {
    final results = <String, Map<String, dynamic>>{};
    
    // First pass: check cache for all drugs
    final uncachedDrugs = <String>[];
    for (final drug in drugNames) {
      final lowerName = drug.toLowerCase().trim();
      final cacheKey = medicineType != null ? "$lowerName:${medicineType.toLowerCase()}" : lowerName;
      
      if (_isCacheValid(cacheKey) && _validationCache.containsKey(cacheKey)) {
        results[drug] = _validationCache[cacheKey]!;
      } else {
        uncachedDrugs.add(drug);
      }
    }
    
    // Second pass: validate uncached drugs in parallel
    if (uncachedDrugs.isNotEmpty) {
      final validationFutures = uncachedDrugs.map((drug) async {
        final result = await validateDrug(drug, medicineType: medicineType);
        return MapEntry(drug, result);
      });
      
      final validationResults = await Future.wait(validationFutures);
      
      for (final entry in validationResults) {
        results[entry.key] = entry.value;
      }
    }
    
    return results;
  }

  Future<Map<String, dynamic>> getDrugInfo(String rxcui) async {
    return await _getDrugDetailsFast(rxcui);
  }

  Future<List<Medicine>> getAllMedicines() async {
    // Implementation for getting all medicines
    return [];
  }
}

class Medicine {
  final String id;
  final String name;
  final String genericName;
  final String category;
  final String description;
  final bool isFromPrescription;
  final String? duration; // <-- Added

  Medicine({
    required this.id,
    required this.name,
    required this.genericName,
    required this.category,
    required this.description,
    required this.isFromPrescription,
    this.duration, // <-- Added
  });
}
