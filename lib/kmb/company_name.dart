import 'package:flutter/material.dart';

/// 支援的運輸公司類型
enum CompanyType {
  kmb,      // 九巴
  ctb,      // 城巴
  lwb,      // 龍運
  nlb,      // 嶼巴
  mtr,      // 港鐵巴士
  lrtfeeder,// 輕鐵接駁巴士
  lightRail,// 輕鐵
  gmb,      // 綠色小巴
  sunferry, // 新渡輪
  fortuneferry, // 富裕小輪
  hkkf,     // 港九小輪
  unknown,  // 未知
}

class CompanyProvider extends ChangeNotifier {
  
  /// 將公司代碼轉換為 CompanyType
  CompanyType getCompanyType(String? co) {
    final code = co?.toLowerCase().trim() ?? '';
    switch (code) {
      case 'kmb': return CompanyType.kmb;
      case 'ctb': return CompanyType.ctb;
      case 'lwb': return CompanyType.lwb;
      case 'nlb': return CompanyType.nlb;
      case 'mtr': return CompanyType.mtr;
      case 'lrtfeeder':
      case 'lrt_feeder':
      case 'lrt-feeder': return CompanyType.lrtfeeder;
      case 'lightrail':
      case 'light_rail':
      case 'light-rail':
      case 'lrt': return CompanyType.lightRail;
      case 'gmb':
      case 'greenminibus': return CompanyType.gmb;
      case 'sunferry':
      case 'sun ferry': return CompanyType.sunferry;
      case 'fortuneferry':
      case 'fortune ferry': return CompanyType.fortuneferry;
      case 'hkkf': return CompanyType.hkkf;
      default: return CompanyType.unknown;
    }
  }
  
  /// 獲取公司名稱
  String getName(String? co, bool isEnglish) {
    final type = getCompanyType(co);
    switch (type) {
      case CompanyType.kmb: return isEnglish ? 'KMB' : '九巴';
      case CompanyType.ctb: return isEnglish ? 'CTB' : '城巴';
      case CompanyType.lwb: return isEnglish ? 'LWB' : '龍運';
      case CompanyType.nlb: return isEnglish ? 'NLB' : '嶼巴';
      case CompanyType.mtr: return isEnglish ? 'MTR' : '港鐵';
      case CompanyType.lrtfeeder: return isEnglish ? 'LRT Feeder' : '港鐵巴士';
      case CompanyType.lightRail: return isEnglish ? 'Light Rail' : '輕鐵';
      case CompanyType.gmb: return isEnglish ? 'GMB' : '專線小巴';
      case CompanyType.sunferry: return isEnglish ? 'Sun Ferry' : '新渡輪';
      case CompanyType.fortuneferry: return isEnglish ? 'Fortune Ferry' : '富裕小輪';
      case CompanyType.hkkf: return isEnglish ? 'HKKF' : '港九小輪';
      case CompanyType.unknown: 
        final code = co?.toUpperCase() ?? '';
        return code.isNotEmpty ? code : (isEnglish ? 'Unknown' : '未知');
    }
  }

  /// 獲取公司主題色
  Color getCompanyColor(String? co) {
    final type = getCompanyType(co);
    switch (type) {
      case CompanyType.kmb: return Colors.red;
      case CompanyType.ctb: return Colors.amber;
      case CompanyType.lwb: return Colors.orange;
      case CompanyType.nlb: return Colors.lightGreen;
      case CompanyType.mtr: return Colors.purple;
      case CompanyType.lrtfeeder: return Colors.teal;
      case CompanyType.lightRail: return Colors.cyan;
      case CompanyType.gmb: return Colors.green;
      case CompanyType.sunferry: return Colors.blue;
      case CompanyType.fortuneferry: return Colors.indigo;
      case CompanyType.hkkf: return Colors.deepPurple;
      case CompanyType.unknown: return Colors.grey;
    }
  }

  /// 背景色 (淡色調)
  Color getBadgeBgColor(String? co, BuildContext context) {
    final type = getCompanyType(co);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = getCompanyColor(co);

    return isDark 
        ? baseColor.withValues(alpha: 0.3) 
        : baseColor.withValues(alpha: 0.15);
  }

  /// 邊框色 (中深色調)
  Color getBadgeBorderColor(String? co, BuildContext context) {
    final type = getCompanyType(co);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = getCompanyColor(co);

    return isDark 
        ? baseColor.withValues(alpha: 0.6) 
        : baseColor.withValues(alpha: 0.8);
  }

  /// 文字色 (最深/最亮色調)
  Color getBadgeTextColor(String? co, BuildContext context) {
    final type = getCompanyType(co);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = getCompanyColor(co);

    // 對於亮色模式，使用深色版本
    if (!isDark) {
      switch (type) {
        case CompanyType.ctb: return const Color.fromARGB(255, 255, 128, 0);
        case CompanyType.kmb: return Colors.red.shade900;
        case CompanyType.lwb: return Colors.orange.shade900;
        case CompanyType.nlb: return Colors.green.shade900;
        case CompanyType.mtr: return Colors.purple.shade900;
        case CompanyType.lrtfeeder: return Colors.teal.shade900;
        case CompanyType.lightRail: return Colors.cyan.shade900;
        case CompanyType.gmb: return Colors.green.shade900;
        case CompanyType.sunferry: return Colors.blue.shade900;
        case CompanyType.fortuneferry: return Colors.indigo.shade900;
        case CompanyType.hkkf: return Colors.deepPurple.shade900;
        case CompanyType.unknown: return Colors.grey.shade900;
      }
    }
    
    // 暗色模式使用淺色
    return baseColor.withValues(alpha: 0.9);
  }
  
  /// 獲取公司圖標
  IconData getCompanyIcon(String? co) {
    final type = getCompanyType(co);
    switch (type) {
      case CompanyType.kmb:
      case CompanyType.ctb:
      case CompanyType.lwb:
      case CompanyType.nlb:
      case CompanyType.mtr:
      case CompanyType.lrtfeeder:
        return Icons.directions_bus;
      case CompanyType.lightRail:
        return Icons.tram;
      case CompanyType.gmb:
        return Icons.local_taxi;
      case CompanyType.sunferry:
      case CompanyType.fortuneferry:
      case CompanyType.hkkf:
        return Icons.directions_boat;
      case CompanyType.unknown:
        return Icons.help_outline;
    }
  }
  
  /// 檢查是否為渡輪服務
  bool isFerry(String? co) {
    final type = getCompanyType(co);
    return type == CompanyType.sunferry || 
           type == CompanyType.fortuneferry || 
           type == CompanyType.hkkf;
  }
  
  /// 檢查是否為鐵路服務
  bool isRail(String? co) {
    final type = getCompanyType(co);
    return type == CompanyType.mtr || 
           type == CompanyType.lightRail || 
           type == CompanyType.lrtfeeder;
  }
  
  /// 檢查是否為巴士服務
  bool isBus(String? co) {
    final type = getCompanyType(co);
    return type == CompanyType.kmb || 
           type == CompanyType.ctb || 
           type == CompanyType.lwb || 
           type == CompanyType.nlb ||
           type == CompanyType.lrtfeeder;
  }
}
