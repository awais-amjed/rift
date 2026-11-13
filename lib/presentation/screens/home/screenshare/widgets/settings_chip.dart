import 'package:material_ui/material_ui.dart';

import '../../../../../data/constants.dart';
import '../../../../common/selectable_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// A chip for picking one value on the share dialog's Advanced page: a
/// resolution, a frame rate, a codec.
///
/// [onTap] null is a value that exists and is not available here, 120 fps at 4K
/// or a bitrate over the server's limit. It stays on screen, greyed: hiding it
/// would leave a shorter row with nothing to explain itself, and somebody who
/// had picked 15 Mbps before would find their setting simply gone.
class SettingsChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const SettingsChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  /// What the chip's words are drawn in, unselected, which the bitrate's box
  /// beside them uses too.
  static const TextStyle restingStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  /// Between the edge and the words, here and in the bitrate's box.
  static const double sidePadding = 10;

  /// How tall a chip is, and the bitrate's box with it: a field's own height
  /// differs from a line of text's by a pixel, which shows side by side.
  static double heightIn(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(28);

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      height: heightIn(context),
      child: Semantics(
        selected: active && enabled,
        child: SelectableSurface(
          selected: active && enabled,
          onTap: onTap,
          // Squarer than the invite chips: these sit in tight rows of short
          // values, where a full pill spends the width on curve.
          borderRadius: BorderRadius.circular(K.radiusRow),
          padding: const EdgeInsets.symmetric(horizontal: sidePadding),
          child: Align(
            widthFactor: 1,
            child: Text(
              label,
              style: !enabled
                  ? AppText.secondary.copyWith(
                      color: context.theme.textTertiary,
                    )
                  : active
                  ? AppText.secondaryStrong
                  : restingStyle,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of [SettingsChip], going onto another line where it runs out of room.
class SettingsChips extends StatelessWidget {
  final List<Widget> children;

  const SettingsChips({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: children,
  );
}
