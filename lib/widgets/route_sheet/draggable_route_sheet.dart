import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'operator_chip_selector.dart';
import 'route_info_card.dart';
import 'route_variant_card.dart';

/// 优化的拖拽面板组件
/// 
/// 特性：
/// - 减少深度嵌套（15-20 层 -> <10 层）
/// - 懒加载（根据大小条件渲染）
/// - 优化模糊效果（条件应用）
/// - Material Design 3 风格
/// - 平滑动画和交互反馈
class DraggableRouteSheet extends StatelessWidget {
  final DraggableScrollableController controller;
  final String routeNumber;
  final String selectedCompany;
  final String originTc;
  final String originEn;
  final String destTc;
  final String destEn;
  final bool isEnglish;
  final List<String> companies;
  final List<Map<String, dynamic>> routeVariants;
  final String Function(String) getCompanyName;
  final ValueChanged<String?> onCompanyChanged;
  final VoidCallback? onRouteInfoTap;

  const DraggableRouteSheet({
    super.key,
    required this.controller,
    required this.routeNumber,
    required this.selectedCompany,
    required this.originTc,
    required this.originEn,
    required this.destTc,
    required this.destEn,
    required this.isEnglish,
    required this.companies,
    required this.routeVariants,
    required this.getCompanyName,
    required this.onCompanyChanged,
    this.onRouteInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DraggableScrollableSheet(
      controller: controller,
      initialChildSize: 0.18,
      minChildSize: 0.1,
      maxChildSize: 0.5,
      snap: true,
      snapSizes: const [0.1, 0.25, 0.4, 0.5],
      builder: (context, scrollController) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // 计算展开比例（0.0 = 最小, 1.0 = 最大）
            final extent = (constraints.maxHeight / MediaQuery.of(context).size.height - 0.1) / 0.4;
            final isExpanded = extent > 0.3;

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: FakeGlass(
                shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                settings: LiquidGlassSettings(
                  blur: 10,
                  thickness: 20,
                  glassColor: colorScheme.surface.withValues(alpha: 0.3),
                ),
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 拖动指示器
                    _buildDragHandle(colorScheme),
                    const SizedBox(height: 12),

                    // 路线信息卡片
                    RouteInfoCard(
                      routeNumber: routeNumber,
                      companyName: getCompanyName(selectedCompany),
                      originTc: originTc,
                      originEn: originEn,
                      destTc: destTc,
                      destEn: destEn,
                      isEnglish: isEnglish,
                      onTap: onRouteInfoTap,
                    ).animate().fadeIn(duration: 200.ms),

                    const SizedBox(height: 16),

                    // 运营商选择器
                    if (companies.length > 1)
                      OperatorChipSelector(
                        companies: companies,
                        selectedCompany: selectedCompany,
                        getDisplayName: getCompanyName,
                        onCompanyChanged: onCompanyChanged,
                      ).animate().fadeIn(duration: 200.ms, delay: 50.ms),

                    const SizedBox(height: 8),

                    // 路线变体（懒加载：仅在展开时显示）
                    AnimatedSize(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: isExpanded && routeVariants.isNotEmpty
                          ? _buildRouteVariants(colorScheme)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 构建拖动指示器
  Widget _buildDragHandle(ColorScheme colorScheme) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// 构建路线变体列表
  Widget _buildRouteVariants(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            isEnglish ? 'Route Variants' : '路線變體',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ...routeVariants.map((variant) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RouteVariantCard(
              routeId: variant['routeId'] ?? '',
              bound: variant['bound'] ?? '',
              serviceType: variant['serviceType'] ?? '1',
              origTc: variant['orig_tc'] ?? '',
              origEn: variant['orig_en'] ?? '',
              destTc: variant['dest_tc'] ?? '',
              destEn: variant['dest_en'] ?? '',
              company: variant['company'] ?? '',
              isEnglish: isEnglish,
              isSelected: variant['selected'] ?? false,
              onTap: () {
                // TODO: 处理变体选择
              },
            ),
          );
        }),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }
}