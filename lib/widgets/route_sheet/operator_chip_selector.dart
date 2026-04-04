import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// 运营商选择器组件
/// 
/// 显示所有可用运营商，支持多选
class OperatorChipSelector extends StatelessWidget {
  final List<String> companies;
  final String? selectedCompany;
  final ValueChanged<String?> onCompanyChanged;
  final String Function(String) getDisplayName;

  const OperatorChipSelector({
    super.key,
    required this.companies,
    this.selectedCompany,
    required this.onCompanyChanged,
    required this.getDisplayName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: companies.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final company = companies[index];
          final isSelected = company == selectedCompany;

          return AnimatedScale(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            scale: isSelected ? 1.05 : 1.0,
            child: FilterChip(
              label: Text(
                getDisplayName(company),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                onCompanyChanged(selected ? company : null);
              },
              selectedColor: colorScheme.primaryContainer,
              checkmarkColor: colorScheme.onPrimaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
            ).animate(target: isSelected ? 1 : 0).fadeIn(duration: 200.ms),
          );
        },
      ),
    );
  }
}