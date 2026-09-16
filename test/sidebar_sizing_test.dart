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

  group('the member list', () {
    test('has its own range', () {
      expect(MembersSidebarSizing.clamp(300, windowWidth: wide), 300);
      expect(
        MembersSidebarSizing.clamp(50, windowWidth: wide),
        K.membersSidebarMinWidth,
      );
      expect(
        MembersSidebarSizing.clamp(900, windowWidth: wide),
        K.membersSidebarMaxWidth,
      );
    });

    test('takes the smallest share of a narrow window', () {
      expect(
        MembersSidebarSizing.clamp(400, windowWidth: 1000),
        1000 * K.membersSidebarMaxWindowFraction,
      );
    });

    test('a corrupt width falls back to the default', () {
      expect(
        MembersSidebarSizing.clamp(double.nan, windowWidth: wide),
        K.membersSidebarWidth,
      );
    });
  });
}
