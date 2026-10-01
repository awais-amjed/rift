import 'dart:math' as math;
import 'dart:ui';

/// Where a reopened window goes: its saved size and position, kept on a
/// screen that exists now.
///
/// The saved geometry is in logical pixels, so the same numbers come out
/// bigger after the display scale goes up — a window saved at 1280×720 on a
/// 1080p screen at 100 % reopens at 1920×1080 physical pixels at 150 %, past
/// the edges and under the taskbar. A monitor unplugged since, or a smaller
/// one, does the same or worse: the whole window off-screen, with nothing to
/// grab. So the window keeps its size where it fits and its place where that
/// is on a screen, and gives up only as much of either as it has to.
///
/// [workAreas] are the displays' usable areas (without the taskbar or dock),
/// in the same logical pixels; [primary] is the one to fall back on when the
/// saved place is on none of them. A null [position] — nothing saved yet —
/// stays null, for the platform to place.
({Size size, Offset? position}) fitWindowToScreens({
  required Size size,
  required Offset? position,
  required List<Rect> workAreas,
  required Rect primary,
}) {
  final area = position == null
      ? primary
      : _mostOverlapped(position & size, workAreas) ?? primary;
  final fitted = Size(
    math.min(size.width, area.width),
    math.min(size.height, area.height),
  );
  if (position == null) return (size: fitted, position: null);
  return (
    size: fitted,
    position: Offset(
      position.dx.clamp(area.left, area.right - fitted.width),
      position.dy.clamp(area.top, area.bottom - fitted.height),
    ),
  );
}

/// The area holding the most of [window], or null when it is on none of
/// them.
Rect? _mostOverlapped(Rect window, List<Rect> areas) {
  Rect? best;
  var bestArea = 0.0;
  for (final area in areas) {
    final overlap = window.intersect(area);
    if (overlap.width <= 0 || overlap.height <= 0) continue;
    final covered = overlap.width * overlap.height;
    if (covered > bestArea) {
      best = area;
      bestArea = covered;
    }
  }
  return best;
}
