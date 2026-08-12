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
  static double maxFor(double windowWidth) {
    final share = windowWidth * K.sidebarMaxWindowFraction;
    return math.max(K.sidebarMinWidth, math.min(K.sidebarMaxWidth, share));
  }

  /// [width] brought inside the bounds for a window of [windowWidth].
  ///
  /// Applied when the width is *read*, not only when it is set: the stored
  /// value outlives the window it was chosen in.
  static double clamp(double width, {required double windowWidth}) {
    if (!width.isFinite) return K.sidebarWidth;
    return width.clamp(K.sidebarMinWidth, maxFor(windowWidth));
  }
}
