import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// A device picker styled as one of the app's fields rather than as a Material
/// dropdown.
///
/// It carries the device's own icon on the left: in a column of two otherwise
/// identical rows, the glyph is what says which one is the microphone and
/// which the speakers, faster than reading either label.
class DeviceDropdown<T> extends StatelessWidget {
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final ThemeState themeState;

  const DeviceDropdown({
    super.key,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: K.fieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: themeState.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: themeState.borderElevated),
      ),
      child: Row(
        spacing: 8,
        children: [
          Icon(icon, size: 16, color: themeState.textTertiary),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                isDense: true,
                dropdownColor: themeState.bgElevated,
                borderRadius: BorderRadius.circular(K.radiusCard),
                icon: Icon(
                  Icons.expand_more_rounded,
                  size: 17,
                  color: themeState.textQuaternary,
                ),
                style: AppText.rowQuiet.copyWith(color: themeState.textPrimary),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
