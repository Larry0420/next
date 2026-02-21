import 'package:flutter/material.dart';

class DirectionStyle {
  final IconData icon;
  final Color color;

  const DirectionStyle({required this.icon, required this.color});

  /// 根據方向字串解析圖示與顏色 (統一使用 Material You 風格)
  factory DirectionStyle.fromDirection(String? dir, BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final direction = (dir ?? '').toUpperCase();

    // 統一 Outbound (去程)
    if (direction.startsWith('O')) {
      return DirectionStyle(
        icon: Icons.arrow_circle_right_outlined,
        color: cs.primary, // M3 系統主色 (通常為藍/紫/等種子色)
      );
    } 
    // 統一 Inbound (回程)
    else if (direction.startsWith('I')) {
      return DirectionStyle(
        icon: Icons.arrow_circle_left_outlined,
        color: cs.tertiary, // M3 第三強調色 (通常為橘/粉/等對比色)
      );
    } 
    // 預設或未知方向
    else {
      return DirectionStyle(
        icon: Icons.arrow_forward_outlined, // 預設箭頭
        color: cs.onSurfaceVariant, // 預設灰色 (M3 次要文字色)
      );
    }
  }
}
