import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A row of swatches, and "none".
///
/// A fixed set rather than a colour wheel. A role's colour is read at a glance
/// against a dark sidebar next to a dozen others, and most of the wheel is
/// either invisible there or indistinguishable from the accent — so the choice
/// worth offering is a small one that all works.
class RoleColourPicker extends StatelessWidget {
  final String? value;
  final ValueChanged<String?>? onChanged;

  const RoleColourPicker({super.key, required this.value, this.onChanged});

  static const List<String> swatches = [
    '#F43F5E', // rose
    '#FB923C', // orange
    '#FBBF24', // amber
    '#22C55E', // emerald
    '#2DD4BF', // teal
    '#38BDF8', // sky
    '#818CF8', // indigo
    '#C084FC', // purple
    '#F472B6', // pink
  ];

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'COLOR',
          style: AppText.sectionLabel.copyWith(color: themeState.textTertiary),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Swatch(
              hex: null,
              selected: value == null,
              onTap: onChanged == null ? null : () => onChanged!(null),
            ),
            for (final hex in swatches)
              _Swatch(
                hex: hex,
                selected: value == hex,
                onTap: onChanged == null ? null : () => onChanged!(hex),
              ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final String? hex;
  final bool selected;
  final VoidCallback? onTap;

  const _Swatch({required this.hex, required this.selected, this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final colour = hex == null
        ? themeState.bgSecondary
        : Color(0xFF000000 | int.parse(hex!.substring(1), radix: 16));

    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: onTap,
      borderRadius: BorderRadius.circular(K.radiusPill),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? themeState.textPrimary : themeState.borderPrimary,
            width: selected ? 2 : 1,
          ),
        ),
        // "None" needs to say so; every other swatch says it by being a colour.
        child: hex == null
            ? Icon(
                Icons.close_rounded,
                size: 13,
                color: themeState.textTertiary,
              )
            : null,
      ),
    );
  }
}
