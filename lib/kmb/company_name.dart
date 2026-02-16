import 'package:flutter/material.dart';

class CompanyProvider extends ChangeNotifier {
  String getName(String? co, bool isEnglish) {
    final code = co?.toUpperCase() ?? '';
    switch (code) {
      case 'KMB': return isEnglish ? 'KMB' : '九巴';
      case 'CTB': return isEnglish ? 'Citybus' : '城巴';
      case 'LWB': return isEnglish ? 'LWB' : '龍運';
      case 'NLB': return isEnglish ? 'NLB' : '嶼巴';
      case 'MTR': return isEnglish ? 'MTR Bus' : '港鐵巴士';
      default: return code;
    }
  }

  Color getColor(String? co, BuildContext context, {Color? fallbackColor}) {
    final code = co?.toUpperCase() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    switch (code) {
      case 'KMB':
        // Vivid red for light, slightly desaturated soft red for dark
        return isDark 
            ? const Color.fromARGB(255, 255, 120, 120) 
            : const Color.fromARGB(255, 212, 45, 27);
      
      case 'CTB':
        // Vibrant yellow for light, amber-tinted yellow for dark readability
        return isDark 
            ? const Color.fromARGB(255, 255, 230, 150) 
            : const Color.fromARGB(255, 204, 146, 0);
      
      case 'LWB':
        return isDark 
            ? const Color(0xFFFFA726) 
            : const Color(0xFFF29100);
      
      case 'NLB':
        return isDark 
            ? const Color.fromARGB(255, 180, 255, 120) 
            : const Color.fromARGB(255, 0, 156, 149);
      
      case 'MTR':
        return isDark 
            ? const Color(0xFF9575CD) 
            : const Color(0xFF532E91);
      
      default:
        return fallbackColor ?? Theme.of(context).colorScheme.primary;
    }
  }

}
