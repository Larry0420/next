import 'package:flutter/material.dart';

class CompanyProvider extends ChangeNotifier {
  String getName(String? co, bool isEnglish) {
    final code = co?.toUpperCase() ?? '';
    switch (code) {
      case 'KMB': return isEnglish ? 'KMB' : '九巴';
      case 'CTB': return isEnglish ? 'CTB' : '城巴';
      case 'LWB': return isEnglish ? 'LWB' : '龍運';
      case 'NLB': return isEnglish ? 'NLB' : '嶼巴';
      case 'MTR': return isEnglish ? 'MTR Bus' : '港鐵巴士';
      default: return code;
    }
  }

    // 1. 背景色 (淡色調)
  Color getBadgeBgColor(String? co, BuildContext context) {
    final code = co?.toUpperCase() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (code) {
      case 'CTB': return isDark ? Colors.amber.shade900.withValues(alpha: 0.3) : Colors.amber.shade100;
      case 'NLB': return isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.lightGreen.shade100;
      case 'LWB': return isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade100;
      case 'MTR': return isDark ? Colors.purple.shade900.withValues(alpha: 0.3) : Colors.purple.shade100;
      case 'KMB':
      default: return isDark ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.red.shade100;
    }
  }

  // 2. 邊框色 (中深色調)
  Color getBadgeBorderColor(String? co, BuildContext context) {
    final code = co?.toUpperCase() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (code) {
      case 'CTB': return isDark ? Colors.amber.shade400 : Colors.amber.shade700;
      case 'NLB': return isDark ? Colors.lightGreen.shade400 : Colors.lightGreen.shade700;
      case 'LWB': return isDark ? Colors.orange.shade400 : Colors.orange.shade700;
      case 'MTR': return isDark ? Colors.purple.shade300 : Colors.purple.shade700;
      case 'KMB':
      default: return isDark ? Colors.red.shade400 : Colors.red.shade700;
    }
  }

  // 3. 文字色 (最深/最亮色調)
  Color getBadgeTextColor(String? co, BuildContext context) {
    final code = co?.toUpperCase() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (code) {
      case 'CTB': return isDark ? Colors.amber.shade100 : const Color.fromARGB(255, 255, 128, 0); // 跟你原本的邏輯：黃底配啡字
      case 'NLB': return isDark ? Colors.lightGreen.shade100 : Colors.green.shade900;
      case 'LWB': return isDark ? Colors.orange.shade100 : Colors.orange.shade900;
      case 'MTR': return isDark ? Colors.purple.shade100 : Colors.purple.shade900;
      case 'KMB':
      default: return isDark ? Colors.red.shade100 : Colors.red.shade900;
    }
  }
}
