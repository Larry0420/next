import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 路线变体卡片组件
/// 
/// 显示不同服务类型和方向的路线变体
class RouteVariantCard extends StatelessWidget {
  final String routeId;
  final String bound;
  final String serviceType;
  final String origTc;
  final String origEn;
  final String destTc;
  final String destEn;
  final String company;
  final bool isEnglish;
  final bool isSelected;
  final VoidCallback onTap;

  const RouteVariantCard({
    super.key,
    required this.routeId,
    required this.bound,
    required this.serviceType,
    required this.origTc,
    required this.origEn,
    required this.destTc,
    required this.destEn,
    required this.company,
    required this.isEnglish,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outline.withValues(alpha: 0.15),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // 服务类型标签
                _buildServiceTypeChip(colorScheme),
                const SizedBox(width: 12),
                // 方向信息
                Expanded(
                  child: _buildDirectionInfo(colorScheme),
                ),
                // 选中指示器
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.check_circle,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ).animate(target: isSelected ? 1 : 0).fadeIn(duration: 200.ms);
  }

  /// 构建服务类型标签
  Widget _buildServiceTypeChip(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'S$serviceType',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected
              ? colorScheme.onPrimary
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// 构建方向信息
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
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isEnglish ? origEn : origTc,
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
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(
              Icons.location_on,
              size: 8,
              color: colorScheme.error,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                isEnglish ? destEn : destTc,
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
        ),
      ],
    );
  }
}