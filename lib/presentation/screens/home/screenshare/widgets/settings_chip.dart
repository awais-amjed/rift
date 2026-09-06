import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';

/// A chip for picking one value in the screen-share settings — a resolution,
/// a frame rate, a codec.
class SettingsChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const SettingsChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableSurface(
      selected: active,
      onTap: onTap,
      // Squarer than the invite chips: these sit in tight rows of three or
      // four short values, where a full pill spends the width on curve.
      borderRadius: BorderRadius.circular(K.radiusRow),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: active
            ? AppText.secondaryStrong
            : AppText.secondary.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}
