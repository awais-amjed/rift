import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

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

  /// A screen rather than a window: which icon stands in for the picture.
  final bool screen;

  /// The window's app (X11's `WM_CLASS`), shown where there is no picture.
  /// Empty where the platform does not say.
  final String app;

  /// The name strip's height, which the grid adds to the picture's.
  static const labelHeight = 38.0;

  const SourceTile({
    super.key,
    required this.label,
    required this.thumbnail,
    required this.minimised,
    required this.selected,
    required this.onTap,
    this.screen = false,
    this.app = '',
  });

  static const _borderWidth = 2.0;
  static const _placeholderIconSize = 28.0;
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
                          _Placeholder(screen: screen, app: app),
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

/// What a tile shows with no picture: one still on its way on Windows, and
/// every tile where the capturer makes none. The app's name, where known, is
/// what tells two windows of one title apart.
class _Placeholder extends StatelessWidget {
  final bool screen;
  final String app;

  const _Placeholder({required this.screen, required this.app});

  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final name = app.trim();
    final style = AppText.meta.copyWith(color: theme.textTertiary);
    return LayoutBuilder(
      builder: (context, constraints) {
        // The smallest tiles leave about 40 px for the picture (see
        // MinimisedPreview): there the icon alone.
        final nameHeight = MediaQuery.textScalerOf(
          context,
        ).scale(style.fontSize! * (style.height ?? 1.4));
        final showName =
            name.isNotEmpty &&
            SourceTile._placeholderIconSize + _gap + nameHeight <=
                constraints.maxHeight;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: _gap,
            children: [
              Icon(
                screen ? Icons.desktop_windows_outlined : Icons.web_asset,
                size: SourceTile._placeholderIconSize,
                color: theme.textQuaternary,
              ),
              if (showName)
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
            ],
          ),
        );
      },
    );
  }
}
