import 'dart:core';

extension StringCasingExtension on String {
  String toTitleCase() {
    if (trim().isEmpty) {
      return '';
    }

    final alphaNumericStart = RegExp(r'^[a-zA-Z0-9]');
    
    // Rare acronyms to maintain as fully uppercase
    const rareTerms = {
      'HKFYG', 'BBI', 'KMB', 'MTR', 'HK', 'VTC', 'IVE', 'HKDI',
      'HKUST', 'HKU', 'CUHK', 'PolyU', 'CityU', 'HKMU', 'THEi',
      'HKCEC', 'AWE', 'YMCA', 'YWCA', 'S.K.H.', 'TWGHs', 'P.L.K.',
      'HKJC', 'JPC', 'FEHD', 'LCSD', 'H.K.', 'PO', 'GPO', 'TE', 'G/F', 'UG/F'
    };

    // Regex for common Roman numerals (1 to 39 approx, covering standard use)
    // Matches I, II, III, IV, V, VI, VII, VIII, IX, X, XI, ... XXXIX
    // We use strict start/end anchor on the core word to avoid matching substrings like "VI" in "VILLAGE"
    final romanRegex = RegExp(r'^(I|II|III|IV|V|VI|VII|VIII|IX|X|XI|XII|XIII|XIV|XV|XVI|XVII|XVIII|XIX|XX|XXX)$');

    return replaceAll(RegExp(' +'), ' ')
        .split(' ')
        .map((str) {
          final upperStr = str.toUpperCase();
          final coreWord = upperStr.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

          // 1. Handle Rare Acronyms
          if (rareTerms.contains(coreWord) || rareTerms.contains(upperStr)) {
            return upperStr;
          }

          // 2. Handle Mixed Codes (e.g., "(SW123)", "3B", "A1")
          if (str.contains(RegExp(r'[a-zA-Z]')) && str.contains(RegExp(r'[0-9]'))) {
            return upperStr;
          }

          // 3. Handle Roman Numerals (e.g. "Phase I", "Block IV")
          // Check if the stripped word is a valid Roman numeral
          if (romanRegex.hasMatch(coreWord)) {
             // If the word was surrounded by brackets (e.g. "(II)"), restore them while keeping "II" upper
             if (!alphaNumericStart.hasMatch(str)) {
                final match = RegExp(r'[a-zA-Z]').firstMatch(str);
                if (match != null) {
                  final i = match.start;
                  // Keep prefix, uppercase the Roman numeral part, keep suffix
                  // Note: simple replacement works because Roman numerals are all uppercase
                  return str.replaceAll(RegExp(r'[a-zA-Z]+'), coreWord);
                }
             }
             return upperStr;
          }

          // 4. Handle words starting with punctuation (e.g., "(GROUND" -> "(Ground")
          if (!alphaNumericStart.hasMatch(str)) {
            final match = RegExp(r'[a-zA-Z]').firstMatch(str);
            if (match == null) return str; 
            
            final i = match.start;
            return str.substring(0, i) + 
                   str[i].toUpperCase() + 
                   str.substring(i + 1).toLowerCase();
          }

          // 5. Standard Title Case
          return '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}';
        })
        .join(' ');
  }
}
