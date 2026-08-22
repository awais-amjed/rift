import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/services/sidebar_sizing.dart';

/// The sidebar's width is dragged by the user and then persisted, so it
/// outlives the window it was chosen in. Both bounds have to hold on the way
/// back out, not just on the way in.
void main() {
  const wide = 1920.0;

  group('within the fixed range', () {
    test('a comfortable width is left alone', () {
      expect(SidebarSizing.clamp(400, windowWidth: wide), 400);
    });

    test('dragging past the floor stops at it', () {
      expect(SidebarSizing.clamp(80, windowWidth: wide), K.sidebarMinWidth);
      expect(SidebarSizing.clamp(0, windowWidth: wide), K.sidebarMinWidth);
      expect(SidebarSizing.clamp(-500, windowWidth: wide), K.sidebarMinWidth);
    });

    test('dragging past the ceiling stops at it', () {
      expect(SidebarSizing.clamp(5000, windowWidth: wide), K.sidebarMaxWidth);
    });
  });

  group('against the window', () {
    // A width chosen on a monitor, then opened on a laptop. Without this the
    // sidebar would swallow the app it is meant to sit beside.
    test('never takes more than its share of a narrower window', () {
      const laptop = 900.0;
      expect(
        SidebarSizing.clamp(K.sidebarMaxWidth, windowWidth: laptop),
        laptop * K.sidebarMaxWindowFraction,
      );
    });

    test('the share only bites when it is tighter than the ceiling', () {
      // Half of this is well past sidebarMaxWidth, so the fixed cap wins.
      expect(SidebarSizing.clamp(5000, windowWidth: 4000), K.sidebarMaxWidth);
    });

    // A sidebar squeezed under the floor is not narrow, it's unusable — so on
    // a window too small to spare half, it takes more than half instead.
    test('the floor outranks the window share', () {
      const tiny = 300.0;
      expect(
        SidebarSizing.clamp(K.sidebarWidth, windowWidth: tiny),
        K.sidebarMinWidth,
      );
      expect(SidebarSizing.clamp(50, windowWidth: tiny), K.sidebarMinWidth);
    });
  });

  group('maxFor', () {
    test('is the ceiling on a wide window and the share on a narrow one', () {
      expect(SidebarSizing.maxFor(wide), K.sidebarMaxWidth);
      expect(SidebarSizing.maxFor(800), 400);
    });

    test('never drops below the floor', () {
      expect(SidebarSizing.maxFor(100), K.sidebarMinWidth);
      expect(SidebarSizing.maxFor(0), K.sidebarMinWidth);
    });
  });

  // Overlaid, the sidebar is covering the content rather than sitting beside
  // it, so the half-the-window rule that protects the content no longer has
  // anything to protect — and on a phone it would spend most of the screen on
  // scrim. A fixed peek is held back instead.
  group('overlaid', () {
    const phone = 390.0;

    /// What is actually left beside the panel once the gutters and the
    /// workspace padding are taken out — the gap a thumb has to land in.
    double peekAt(double windowWidth) =>
        windowWidth -
        SidebarSizing.maxFor(windowWidth, overlay: true) -
        K.sidebarOverlayChrome;

    test('runs wider than the docked share would allow', () {
      expect(
        SidebarSizing.maxFor(phone, overlay: true),
        greaterThan(SidebarSizing.maxFor(phone)),
      );
    });

    test('leaves the whole peek showing, not what the gutters left over', () {
      // Counting only the panel is the bug this pins: the four gutters around
      // it ate most of the gap, and a 420px window showed a 34px sliver that
      // read as a squeezed column rather than as content behind a drawer.
      expect(peekAt(phone), K.sidebarOverlayPeek);
      for (final width in [phone, 430.0, 600.0]) {
        expect(
          peekAt(width),
          greaterThanOrEqualTo(K.sidebarOverlayPeek),
          reason: 'a ${width}px window would be covered nearly edge to edge',
        );
      }
    });

    test('below the floor the peek gives way, but never vanishes', () {
      // A 360px window cannot afford both the minimum panel and the full peek.
      // The floor wins — a panel too narrow to read is worse than a thin gap —
      // but there is still something left to tap, which is the part that would
      // strand you if it went to zero.
      expect(SidebarSizing.maxFor(360, overlay: true), K.sidebarMinWidth);
      expect(peekAt(360), greaterThan(0));
      expect(peekAt(320), greaterThan(0));
    });

    test('is still held to the drag ceiling on a wide window', () {
      expect(SidebarSizing.maxFor(2000, overlay: true), K.sidebarMaxWidth);
    });

    test('the floor still outranks the peek', () {
      // A 200px window cannot honour both. Which one gives is the difference
      // between a panel that runs off the edge and one too narrow to read.
      expect(SidebarSizing.maxFor(200, overlay: true), K.sidebarMinWidth);
    });

    test('a docked width is not carried into the overlay unchanged', () {
      // Same stored preference, two different windows to satisfy.
      expect(
        SidebarSizing.clamp(K.sidebarWidth, windowWidth: phone, overlay: true),
        lessThan(K.sidebarWidth),
      );
      expect(peekAt(phone), K.sidebarOverlayPeek);
    });
  });

  // The stored value comes back through JSON, and a corrupt one shouldn't
  // leave the layout with a NaN width to lay out.
  test('a nonsense stored width falls back to the default', () {
    expect(SidebarSizing.clamp(double.nan, windowWidth: wide), K.sidebarWidth);
    expect(
      SidebarSizing.clamp(double.infinity, windowWidth: wide),
      K.sidebarWidth,
    );
  });

  test('the floor leaves the channel column usable beside the rail', () {
    // The rail is fixed, so the floor is really a floor on what is left for
    // channel names — and it has to stay above what the shared widgets in it
    // are tested down to.
    expect(K.sidebarMinWidth - K.serverRailWidth, greaterThan(120));
  });
}
