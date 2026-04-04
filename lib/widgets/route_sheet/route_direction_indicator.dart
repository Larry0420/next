import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 方向指示器组件
/// 
/// 显示路线的起点和终点，带有图标和动画效果
class RouteDirectionIndicator extends StatelessWidget {
  final String originTc;
  final String originEn;
  final String destTc;
  final String destEn;
  final bool isEnglish;
  final VoidCallback? onTap;

  const RouteDirectionIndicator({
    super.key,
    required this.originTc,
    required this.originEn,
    required this.destTc,
    required this.destEn,
    required this.isEnglish,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.15),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // 起点
              Expanded(
                child: _buildDirectionRow(
                  icon: Icons.circle,
                  iconColor: colorScheme.primary,
                  text: isEnglish ? originEn : originTc,
                  colorScheme: colorScheme,
                ),
              ),
              // 分隔符
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
              // 终点
              Expanded(
                child: _buildDirectionRow(
                  icon: Icons.location_on,
                  iconColor: colorScheme.error,
                  text: isEnglish ? destEn : destTc,
                  colorScheme: colorScheme,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建单行方向信息
  Widget _buildDirectionRow({
    required IconData icon,
    required Color iconColor,
    required String text,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 12,
          color: iconColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}