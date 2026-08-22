import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/data/enums/layout_mode.dart';

/// The one decision every responsive branch in the app is made from.
///
/// Worth pinning precisely because it is invisible: a boundary off by a pixel
/// does not throw, it just docks a sidebar into a window that cannot hold it,
/// and the first anyone knows is a row of overflow stripes on one device.
void main() {
  group('LayoutMode.forWidth', () {
    test('a phone is compact', () {
      expect(LayoutMode.forWidth(320), LayoutMode.compact); // small phone
      expect(LayoutMode.forWidth(390), LayoutMode.compact); // iPhone-ish
      expect(LayoutMode.forWidth(430), LayoutMode.compact); // large phone
    });

    test('a tablet and a half-screen window are medium', () {
      expect(LayoutMode.forWidth(768), LayoutMode.medium); // portrait tablet
      expect(LayoutMode.forWidth(960), LayoutMode.medium); // half of 1920
    });

    test('a desktop window is expanded', () {
      expect(LayoutMode.forWidth(1280), LayoutMode.expanded);
      expect(LayoutMode.forWidth(3840), LayoutMode.expanded);
    });

    test('each boundary belongs to the roomier mode', () {
      // Inclusive on the way up, so a window sitting exactly on a breakpoint
      // gets the layout the breakpoint is named for rather than the one below.
      expect(LayoutMode.forWidth(K.breakpointMedium), LayoutMode.medium);
      expect(LayoutMode.forWidth(K.breakpointMedium - 1), LayoutMode.compact);
      expect(LayoutMode.forWidth(K.breakpointExpanded), LayoutMode.expanded);
      expect(LayoutMode.forWidth(K.breakpointExpanded - 1), LayoutMode.medium);
    });

    test('a degenerate width still resolves', () {
      // Windows report zero mid-restore, and the layout has to answer rather
      // than throw on the frame before a real size arrives.
      expect(LayoutMode.forWidth(0), LayoutMode.compact);
    });
  });

  group('what docks at each size', () {
    test('the sidebar docks everywhere but a phone', () {
      expect(LayoutMode.compact.sidebarIsOverlay, isTrue);
      expect(LayoutMode.medium.sidebarIsOverlay, isFalse);
      expect(LayoutMode.expanded.sidebarIsOverlay, isFalse);
    });

    test('the member list docks only when everything fits', () {
      expect(LayoutMode.compact.membersIsOverlay, isTrue);
      expect(LayoutMode.medium.membersIsOverlay, isTrue);
      expect(LayoutMode.expanded.membersIsOverlay, isFalse);
    });

    test('a docked pane is never also overlaid', () {
      // Both at once would mount the same panel twice — one in the row and one
      // in the stack — and the second would silently win.
      for (final mode in LayoutMode.values) {
        expect(
          mode.sidebarIsOverlay && !mode.membersIsOverlay,
          isFalse,
          reason:
              '$mode would overlay the sidebar while docking the member list, '
              'which is narrower and would have gone first',
        );
      }
    });
  });

  test('the breakpoints leave room for what they promise to dock', () {
    // medium claims a docked sidebar fits. It only does if the window can hold
    // the sidebar at its floor and still leave a usable chat column.
    expect(K.breakpointMedium, greaterThan(K.sidebarMinWidth + 300));
    // expanded claims the member list fits too, on top of that.
    expect(
      K.breakpointExpanded,
      greaterThan(K.breakpointMedium + K.membersSidebarWidth),
    );
  });
}
