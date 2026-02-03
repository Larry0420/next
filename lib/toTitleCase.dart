import 'dart:core';

extension StringCasingExtension on String {
  String toTitleCase() {
    if (trim().isEmpty) {
      return '';
    }

    // Rare acronyms to maintain as fully uppercase
    const rareTerms = {
      'HKFYG', 'BBI', 'KMB', 'MTR', 'HK', 'VTC', 'IVE', 'HKDI',
      'HKUST', 'HKU', 'CUHK', 'PolyU', 'CityU', 'HKMU', 'THEi',
      'HKCEC', 'AWE', 'YMCA', 'YWCA', 'S.K.H.', 'TWGHs', 'P.L.K.',
      'HKJC', 'JPC', 'FEHD', 'LCSD', 'H.K.', 'GPO', 'TE', 'G/F', 'UG/F', 'II', 'I', 'HZMB', 'GTC'
    };

    final alphaNumericStart = RegExp(r'^[a-zA-Z0-9]');
    
    // Split by whitespace OR hyphens. 
    // This ensures "Bus-Bus" is treated as two separate words: "Bus" and "Bus".
    return splitMapJoin(
      RegExp(r'(\s+|-)'), 
      onMatch: (m) {
        // Normalize whitespace to a single space, but keep hyphens as-is.
        final match = m.group(0)!;
        return match.contains('-') ? match : ' ';
      },
      onNonMatch: (str) {
        if (str.isEmpty) return '';

        final upperStr = str.toUpperCase();
        final coreWord = upperStr.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

        // 1. Handle Rare Acronyms (e.g. "(HKFYG)" or "G/F")
        if (rareTerms.contains(coreWord) || rareTerms.contains(upperStr)) {
          return upperStr;
        }

        // 2. Handle Mixed Codes (e.g., "(SW123)", "3B", "A1")
        if (str.contains(RegExp(r'[a-zA-Z]')) && str.contains(RegExp(r'[0-9]'))) {
          return upperStr;
        }

        // 3. Handle words starting with punctuation (e.g., "(GROUND" -> "(Ground")
        if (!alphaNumericStart.hasMatch(str)) {
          final match = RegExp(r'[a-zA-Z]').firstMatch(str);
          if (match == null) return str; // No letters found (e.g. "(123)")
          
          final i = match.start;
          return str.substring(0, i) + 
                 str[i].toUpperCase() + 
                 str.substring(i + 1).toLowerCase();
        }

        // 4. Standard Title Case
        return '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}';
      },
    );
  }
}