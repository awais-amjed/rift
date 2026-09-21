import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/constants.dart';
import '../../logic/cubits/theme/theme_cubit.dart';
import '../responsive/shell_scope.dart';

/// One of the app's floating panels — sidebar, content, members.
///
/// On a desktop the redesign has no full-bleed surfaces: every region is a
/// rounded, bordered panel sitting on the canvas with a gutter around it. That
/// chrome lives here so the panels can't drift apart from each other.
///
/// **On a phone there is no canvas to float on.** The panel becomes the
/// screen: no gutter, no border, no rounded corners — see
/// `LayoutMode.panelsAreIslands` for why. That also makes this the right place
/// to hold the display's cutouts off the content, because the surface should
/// run *under* the status bar and the home indicator while the content inside
/// it stops short of them. Insetting the workspace instead left a band of
/// backdrop at each end of the screen, which is the tell that a layout was
/// drawn for a rectangle and then handed a phone.
///
/// Content panels (chat, voice stage, settings body) pass
/// `color: theme.bgContent`; chrome panels take the default.
class AppPanel extends StatelessWidget {
  final Widget child;

  /// Panel background. Defaults to the chrome surface (`bgSecondary`).
  final Color? color;

  /// Fixed width, for panels that don't flex (sidebar, members).
  final double? width;

  /// Cast when the panel floats over other panels rather than sitting beside
  /// them — a drawer over the content. Survives the flattening on a phone:
  /// the shadow is the only thing left saying which is on top.
  final List<BoxShadow>? shadow;

  /// Overrides the corners. For a drawer on a phone, which is flush against
  /// the screen edge on one side — square there, rounded on the side facing
  /// the content, the way a sheet that slid in from off-screen would be.
  final BorderRadius? borderRadius;

  /// How far an island has melted into the window: 0 is the floating panel,
  /// 1 is square and borderless. In between is the transition, so a caller
  /// animates this rather than swapping panels. See `ShellScope.immersive`.
  final double bleed;

  const AppPanel({
    super.key,
    required this.child,
    this.color,
    this.width,
    this.shadow,
    this.borderRadius,
    this.bleed = 0,
  });

  @override
  Widget build(BuildContext context) {
    final islands = context.layoutMode.panelsAreIslands;
    final corner = K.radiusCard * (1 - bleed);
    final radius =
        borderRadius ??
        (islands ? BorderRadius.circular(corner) : BorderRadius.zero);

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: color ?? themeState.bgSecondary,
            borderRadius: radius,
            // A border traces the edge of an island. Against the screen's own
            // edge it is a hairline of not-quite-black that reads as a
            // rendering fault rather than a boundary.
            border: islands
                ? Border.all(
                    color: themeState.borderPrimary.withValues(
                      alpha: themeState.borderPrimary.a * (1 - bleed),
                    ),
                  )
                : null,
            boxShadow: shadow,
          ),
          child: ClipRRect(
            // The border is painted inside the box, so the clip shrinks by its
            // width or children bleed over it at the corners. Nothing to
            // shrink by where there is no border.
            borderRadius: islands
                ? BorderRadius.circular((corner - 1).clamp(0, K.radiusCard))
                : radius,
            // Only where the panel is the screen. While it is an island the
            // workspace is already clear of everything, and a second inset
            // here would push the content in twice.
            child: islands ? child : SafeArea(child: child),
          ),
        );
      },
    );
  }
}
