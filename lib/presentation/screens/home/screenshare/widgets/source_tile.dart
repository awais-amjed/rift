import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/hover_builder.dart';
import '../../../../theme/app_motion.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'minimised_preview.dart';

/// One window or screen in the share dialog's list: its picture, and its name
/// on a strip below.
///
/// The hover shows on the border: a picture fills the tile, and ink would be
/// drawn underneath it.
class SourceTile extends StatelessWidget {
  final String label;
  final Uint8List? thumbnail;
  final bool minimised;
  final bool selected;
  final VoidCallback onTap;

  /// The name strip's height, which the grid adds to the picture's.
  static const labelHeight = 38.0;

  const SourceTile({
    super.key,
    required this.label,
    required this.thumbnail,
    required this.minimised,
    required this.selected,
    required this.onTap,
  });

  static const _borderWidth = 2.0;
  static const _waitingIconSize = 28.0;
  static const _badgeSize = 24.0;
  static const _badgeInset = 8.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final radius = BorderRadius.circular(K.radiusRow);
    final picture = thumbnail;
    return HoverBuilder(
      builder: (context, hovered) => Semantics(
        selected: selected,
        child: Material(
          color: selected ? theme.channelActiveBg : theme.bgTertiary,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.react,
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  width: _borderWidth,
                  color: selected
                      ? theme.primary
                      : hovered
                      ? theme.channelActiveBorder
                      : theme.borderPrimary,
                ),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: theme.bgContent),
                        if (picture != null)
                          Image.memory(
                            picture,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          )
                        else if (minimised)
                          const MinimisedPreview()
                        else
                          Icon(
                            Icons.desktop_windows_outlined,
                            size: _waitingIconSize,
                            color: theme.textQuaternary,
                          ),
                        if (selected) const _Badge(),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: labelHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: (selected ? AppText.row : AppText.rowQuiet)
                              .copyWith(
                                color: selected
                                    ? theme.channelActiveText
                                    : theme.textSecondary,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Positioned(
      top: SourceTile._badgeInset,
      right: SourceTile._badgeInset,
      child: Container(
        width: SourceTile._badgeSize,
        height: SourceTile._badgeSize,
        decoration: BoxDecoration(color: theme.primary, shape: BoxShape.circle),
        child: Icon(Icons.check, size: K.iconRow, color: theme.onPrimary),
      ),
    );
  }
}
