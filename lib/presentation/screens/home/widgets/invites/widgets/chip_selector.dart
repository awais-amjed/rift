import 'package:flutter/material.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../theme/custom_colors.dart';

/// A row of equal-width tappable chips where exactly one is selected at a time.
class ChipSelector extends StatelessWidget {
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ThemeState themeState;

  const ChipSelector({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(options.length, (i) {
        final selected = i == selectedIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < options.length - 1 ? 6 : 0),
            child: GestureDetector(
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? CustomColors.primary.withValues(alpha: 0.12)
                      : themeState.bgSecondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? CustomColors.primary.withValues(alpha: 0.5)
                        : themeState.borderPrimary,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? CustomColors.primary
                          : themeState.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

