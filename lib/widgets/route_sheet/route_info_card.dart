import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 优化的路线信息卡片组件
/// 
/// 减少 widget 嵌套层级，提升渲染性能
/// 使用 Material Design 3 组件和样式
class RouteInfoCard extends StatelessWidget {
  final String routeNumber;
  final String companyName;
  final String originTc;
  final String originEn;
  final String destTc;
  final String destEn;
  final bool isEnglish;
  final VoidCallback? onTap;

  const RouteInfoCard({
    super.key,
    required this.routeNumber,
    required this.companyName,
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              // 路线号和公司
              _buildRouteInfo(colorScheme),
              const SizedBox(width: 6),
              // 路线起点和终点
              Expanded(
                child: _buildDirectionInfo(colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建路线号和公司信息
  Widget _buildRouteInfo(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                routeNumber,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                companyName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            width: 36,
            height: 36,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.directions_bus,
              color: colorScheme.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建方向信息（起点和终点）
  Widget _buildDirectionInfo(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.circle,
              size: 8,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isEnglish ? originEn : originTc,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(
              Icons.location_on,
              size: 8,
              color: colorScheme.error,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isEnglish ? destEn : destTc,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}