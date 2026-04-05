import 'package:flutter/material.dart';

/// Unified ETA formatter for route status pages
/// 
/// Provides:
/// - Consistent ETA time formatting across all bus companies
/// - Relative time display (e.g., "2 min ago", "5 min")
/// - Language-aware formatting (English/Traditional Chinese)
/// - Scheduling status display (Scheduled, Arriving, Departed)
class EtaFormatter {
  EtaFormatter({required this.isEnglish});
  
  final bool isEnglish;
  
  /// Format ETA time for display
  /// 
  /// Parameters:
  /// - etaTime: The ETA time as a string (format: "HH:mm:ss")
  /// - currentTime: Optional current time for relative calculation
  /// - useRelativeTime: Whether to use relative time format
  /// 
  /// Returns formatted time string
  String formatEta(
    String etaTime, {
    DateTime? currentTime,
    bool useRelativeTime = true,
  }) {
    if (etaTime.isEmpty) return '-';
    
    // Parse ETA time
    final parts = etaTime.split(':');
    if (parts.length < 3) return etaTime;
    
    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final second = int.parse(parts[2]);
      
      final now = currentTime ?? DateTime.now();
      final etaDate = DateTime(now.year, now.month, now.day, hour, minute, second);
      
      // Handle next day case
      final etaDateTime = etaDate.isBefore(now) 
          ? etaDate.add(const Duration(days: 1)) 
          : etaDate;
      
      final difference = etaDateTime.difference(now);
      
      if (useRelativeTime) {
        return formatRelativeTime(difference);
      }
      
      return formatAbsoluteTime(etaDateTime);
    } catch (e) {
      return etaTime;
    }
  }
  
  /// Format relative time (e.g., "5 min", "Arriving")
  String formatRelativeTime(Duration difference) {
    final minutes = difference.inMinutes;
    final seconds = difference.inSeconds;
    
    if (minutes == 0 && seconds <= 30) {
      return isEnglish ? 'Arriving' : '即將抵達';
    }
    
    if (minutes == 0) {
      return isEnglish ? '< 1 min' : '< 1 分鐘';
    }
    
    if (isEnglish) {
      return '$minutes min';
    }
    
    return '$minutes 分鐘';
  }
  
  /// Format absolute time (e.g., "14:30")
  String formatAbsoluteTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  
  /// Format departure/arrival status
  /// 
  /// Parameters:
  /// - status: The status string from API
  /// - etaTime: Optional ETA time for context
  /// 
  /// Returns formatted status string
  String formatStatus(String status, {String? etaTime}) {
    if (status.isEmpty) {
      return isEnglish ? 'Scheduled' : '班次';
    }
    
    // Common status mappings
    final lowerStatus = status.toLowerCase();
    
    if (lowerStatus.contains('arrival') || lowerStatus.contains('arriving')) {
      return isEnglish ? 'Arriving' : '即將抵達';
    }
    
    if (lowerStatus.contains('departed') || lowerStatus.contains('left')) {
      return isEnglish ? 'Departed' : '已開出';
    }
    
    if (lowerStatus.contains('schedule')) {
      return isEnglish ? 'Scheduled' : '班次';
    }
    
    if (lowerStatus.contains('cancelled')) {
      return isEnglish ? 'Cancelled' : '取消';
    }
    
    // Return original status if not recognized
    return status;
  }
  
  /// Format ETA with relative time and status
  /// 
  /// Parameters:
  /// - etaTime: The ETA time string
  /// - status: The status string
  /// - currentTime: Optional current time
  /// 
  /// Returns formatted string combining time and status
  String formatEtaWithStatus(
    String etaTime,
    String status, {
    DateTime? currentTime,
  }) {
    final formattedTime = formatEta(etaTime, currentTime: currentTime);
    final formattedStatus = formatStatus(status, etaTime: etaTime);
    
    if (formattedTime == '-' || formattedTime.isEmpty) {
      return formattedStatus;
    }
    
    return '$formattedTime ($formattedStatus)';
  }
  
  /// Calculate minutes until arrival
  /// 
  /// Parameters:
  /// - etaTime: The ETA time string
  /// - currentTime: Optional current time
  /// 
  /// Returns minutes until arrival, or null if invalid
  int? calculateMinutesUntil(String etaTime, {DateTime? currentTime}) {
    if (etaTime.isEmpty) return null;
    
    final parts = etaTime.split(':');
    if (parts.length < 3) return null;
    
    try {
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final second = int.parse(parts[2]);
      
      final now = currentTime ?? DateTime.now();
      final etaDate = DateTime(now.year, now.month, now.day, hour, minute, second);
      
      final etaDateTime = etaDate.isBefore(now) 
          ? etaDate.add(const Duration(days: 1)) 
          : etaDate;
      
      return etaDateTime.difference(now).inMinutes;
    } catch (e) {
      return null;
    }
  }
  
  /// Check if ETA is arriving soon (within 2 minutes)
  bool isArrivingSoon(String etaTime, {DateTime? currentTime}) {
    final minutes = calculateMinutesUntil(etaTime, currentTime: currentTime);
    return minutes != null && minutes <= 2;
  }
  
  /// Check if ETA has already passed
  bool isPast(String etaTime, {DateTime? currentTime}) {
    final minutes = calculateMinutesUntil(etaTime, currentTime: currentTime);
    return minutes != null && minutes < 0;
  }
}