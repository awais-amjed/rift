import 'dart:math' as math;

import '../../data/constants.dart';

/// How wide the sidebar is allowed to be.
///
/// Two bounds, and they can disagree: a fixed range the user drags within, and
/// a share of the window so the sidebar can never crowd out the content. The
/// window one has to win — a width chosen on a wide monitor would otherwise
/// swallow the app when the same vault is opened on a laptop.
///
/// The floor wins over both. A sidebar squeezed below [K.sidebarMinWidth] is
/// not a narrow sidebar, it's an unusable one, so on a window too small to give
/// it half the space it takes more than half rather than collapsing.
class SidebarSizing {
  const SidebarSizing._();

  /// The widest the sidebar may be in a window of [windowWidth].
  ///
  /// [overlay] swaps the window share for a fixed peek. Half the window is the
  /// right ceiling for a docked sidebar, whose whole purpose is to sit beside
  /// the content — but an overlaid one is covering the content anyway, and on
  /// a phone half of 390 is a channel list squeezed to nothing for the sake of
  /// a scrim nobody needs that much of. [K.sidebarOverlayPeek] is what is held
  /// back instead: enough content left showing to tap on, and to say what the
  /// drawer is sitting in front of. [K.sidebarOverlayChrome] comes off too —
  /// the gutters and workspace padding are between the panel and that peek,
  /// not part of it.
  static double maxFor(double windowWidth, {bool overlay = false}) {
    final share = overlay
        ? windowWidth - K.sidebarOverlayPeek - K.sidebarOverlayChrome
        : windowWidth * K.sidebarMaxWindowFraction;
    return math.max(K.sidebarMinWidth, math.min(K.sidebarMaxWidth, share));
  }

  /// [width] brought inside the bounds for a window of [windowWidth].
  ///
  /// Applied when the width is *read*, not only when it is set: the stored
  /// value outlives the window it was chosen in.
  static double clamp(
    double width, {
    required double windowWidth,
    bool overlay = false,
  }) {
    if (!width.isFinite) return K.sidebarWidth;
    return width.clamp(
      K.sidebarMinWidth,
      maxFor(windowWidth, overlay: overlay),
    );
  }
}
