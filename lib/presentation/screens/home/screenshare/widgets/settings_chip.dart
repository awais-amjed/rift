import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A chip for picking one value in the screen-share settings — a resolution,
/// a frame rate, a codec.
///
/// [enabled] false is a value that exists and is not available here, which is
/// a different thing from one that does not exist. A bitrate the server will
/// not carry stays on screen, greyed: hiding it would leave a shorter row
/// with nothing to explain itself, and somebody who had picked 15 Mbps
/// before would find their setting simply gone.
class SettingsChip extends StatelessWidget {
  final String label;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const SettingsChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SelectableSurface(
      selected: active && enabled,
      // A null tap is what makes it inert: no press, no hover, no cursor.
      onTap: enabled ? onTap : null,
      // Squarer than the invite chips: these sit in tight rows of three or
      // four short values, where a full pill spends the width on curve.
      borderRadius: BorderRadius.circular(K.radiusRow),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Text(
        label,
        style: !enabled
            ? AppText.secondary.copyWith(color: context.theme.textTertiary)
            : active
            ? AppText.secondaryStrong
            : AppText.secondary.copyWith(fontWeight: FontWeight.w500),
      ),
    );
  }
}
