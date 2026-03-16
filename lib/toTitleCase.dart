import 'dart:core';

extension StringCasingExtension on String {
  String toTitleCase() {
    if (trim().isEmpty) return '';

    // Acronyms / codes to preserve as-is (case-sensitive set)
    const preservedTerms = {
      // Transport operators
      'KMB', 'MTR', 'NLB', 'CTB', 'LWB', 'GMB', 'NWFB',
      // Universities & education
      'HKU', 'HKUST', 'CUHK', 'PolyU', 'CityU', 'HKMU', 'THEi',
      'VTC', 'IVE', 'HKDI',
      // Organisations
      'HKFYG', 'BBI', 'YMCA', 'YWCA', 'TWGHs', 'S.K.H.', 'P.L.K.',
      'HKJC', 'JPC',
      // Government / infrastructure
      'FEHD', 'LCSD', 'GPO', 'HZMB', 'GTC', 'AWE',
      'HKCEC',
      // Geographic abbreviations
      'HK', 'H.K.',
      // Floor / structural codes
      'G/F', 'UG/F',
      // Roman numerals (standalone)
      'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X',
      // Misc
      'TE',
    };

    // Connective words that should stay lowercase (unless first word)
    const lowerWords = {
      'a', 'an', 'the',
      'and', 'but', 'or', 'nor',
      'at', 'by', 'for', 'in', 'of', 'on', 'to', 'up', 'via',
    };

    final alphaNumericStart = RegExp(r'^[a-zA-Z0-9]');
    bool isFirstWord = true;

    return splitMapJoin(
      RegExp(r'(\s+|-)'),
      onMatch: (m) {
        final match = m.group(0)!;
        // Preserve hyphens; normalise all whitespace runs to single space
        return match.contains('-') ? match : ' ';
      },
      onNonMatch: (str) {
        if (str.isEmpty) return '';

        final upperStr   = str.toUpperCase();
        // Strip punctuation to get the bare alphabetic/numeric core
        final coreWord   = str.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
        final upperCore  = coreWord.toUpperCase();

        // ── Rule 1: Preserved terms (case-sensitive first, then upper fallback) ──
        // Match original casing first (e.g. "PolyU", "THEi", "TWGHs")
        if (preservedTerms.contains(coreWord) ||
            preservedTerms.contains(upperCore) ||
            preservedTerms.contains(upperStr)) {
          isFirstWord = false;
          // Reconstruct: keep surrounding punctuation, restore preserved term
          final termToUse = preservedTerms.firstWhere(
            (t) => t.toUpperCase() == upperCore,
            orElse: () => upperCore,
          );
          return str.replaceAll(RegExp(r'[a-zA-Z0-9]+'), termToUse);
        }

        // ── Rule 2: Mixed alphanumeric codes (e.g. "3B", "A1", "SW123") ──
        if (coreWord.contains(RegExp(r'[a-zA-Z]')) &&
            coreWord.contains(RegExp(r'[0-9]'))) {
          isFirstWord = false;
          return upperStr;
        }

        // ── Rule 3: Pure numeric tokens (e.g. "123", "(2)") ──
        if (coreWord.isNotEmpty && int.tryParse(coreWord) != null) {
          isFirstWord = false;
          return str;
        }

        // ── Rule 4: Connective / short words (keep lowercase unless first) ──
        final lowerCore = coreWord.toLowerCase();
        if (!isFirstWord && lowerWords.contains(lowerCore)) {
          return str.toLowerCase();
          // note: isFirstWord stays false
        }

        // ── Rule 5: Starts with punctuation (e.g. "(ground" → "(Ground") ──
        if (!alphaNumericStart.hasMatch(str)) {
          final letterMatch = RegExp(r'[a-zA-Z]').firstMatch(str);
          if (letterMatch == null) {
            // Pure punctuation / numeric, no letters
            isFirstWord = false;
            return str;
          }
          final i = letterMatch.start;
          isFirstWord = false;
          return str.substring(0, i) +
              str[i].toUpperCase() +
              str.substring(i + 1).toLowerCase();
        }

        // ── Rule 6: Standard title case ──
        isFirstWord = false;
        return '${str[0].toUpperCase()}${str.substring(1).toLowerCase()}';
      },
    );
  }
}
