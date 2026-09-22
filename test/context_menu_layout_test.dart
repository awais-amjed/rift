import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/context_menu/context_menu_layout.dart';

/// A context menu is sized by its content, so where it goes has to be worked
/// out from the size it actually turned out to be.
///
/// It used to be worked out from a guessed 320px. Opening downward pinned the
/// top edge to the cursor and looked right; flipping upward subtracted the
/// guess rather than the real height, so a short menu floated a long way above
/// the row that opened it.
void main() {
  const screen = Size(1280, 720);
  const menu = Size(232, 200);
  const margin = 8.0;

  Offset place(Offset target, {Size child = menu, Size within = screen}) =>
      ContextMenuLayout.atPoint(target).getPositionForChild(within, child);

  group('opening downward', () {
    test('pins the top edge to the cursor', () {
      const target = Offset(400, 100);
      expect(place(target), target);
    });
  });

  group('opening upward', () {
    test('pins the bottom edge to the cursor, whatever the height', () {
      // Near the bottom, so it has to flip.
      const target = Offset(400, 690);

      for (final height in [120.0, 200.0, 300.0]) {
        final position = place(target, child: Size(menu.width, height));
        expect(
          position.dy + height,
          target.dy,
          reason: 'a ${height}px menu should end at the cursor, not above it',
        );
      }
    });

    test('the gap above the cursor is the same as the gap below it', () {
      const short = Size(232, 120);
      final down = place(const Offset(400, 100), child: short);
      final up = place(const Offset(400, 690), child: short);

      expect(down.dy - 100, 0, reason: 'down: top edge sits on the cursor');
      expect(690 - (up.dy + short.height), 0, reason: 'up: bottom edge does');
    });
  });

  group('choosing a side', () {
    test('stays down when it fits, even close to the bottom', () {
      // 200 tall with 220 of room below: no reason to flip.
      const target = Offset(400, 492);
      expect(place(target).dy, target.dy);
    });

    test('stays down when neither side has room', () {
      // Taller than the screen: flipping up would only be worse.
      const tall = Size(232, 800);
      final position = place(const Offset(400, 300), child: tall);
      expect(position.dy, margin);
    });
  });

  group('horizontal', () {
    test('pins the left edge to the cursor when there is room', () {
      expect(place(const Offset(400, 100)).dx, 400);
    });

    test('pins the right edge to the cursor when there is not', () {
      const target = Offset(1200, 100);
      final position = place(target);
      expect(position.dx + menu.width, target.dx);
    });
  });

  test('never leaves the screen', () {
    for (final target in [
      const Offset(0, 0),
      const Offset(1280, 720),
      const Offset(1279, 1),
      const Offset(1, 719),
    ]) {
      final position = place(target);
      expect(position.dx, greaterThanOrEqualTo(margin));
      expect(position.dy, greaterThanOrEqualTo(margin));
      expect(
        position.dx + menu.width,
        lessThanOrEqualTo(screen.width - margin),
      );
      expect(
        position.dy + menu.height,
        lessThanOrEqualTo(screen.height - margin),
      );
    }
  });

  // A submenu hangs off the row that opened it, not off a point. Both edges of
  // that row matter: it opens past the right one, and when it can't fit there
  // it has to open before the *left* one. Pivoting about a single point put the
  // submenu's right edge on the parent panel's right edge — straight on top of
  // the menu it belongs to.
  group('anchored to a row', () {
    // A 232-wide parent panel sitting hard against the right of the screen.
    const panelLeft = 1030.0;
    const panelRight = 1262.0;
    const row = Rect.fromLTRB(panelLeft, 300, panelRight, 336);
    const submenu = Size(240, 160);

    Offset place(Rect anchor, {Size child = submenu}) =>
        ContextMenuLayout(anchor: anchor).getPositionForChild(screen, child);

    test('opens past the row when there is room to the right', () {
      const roomy = Rect.fromLTRB(200, 300, 432, 336);
      expect(place(roomy).dx, roomy.right);
    });

    test('flips clear of the panel, not across it', () {
      final position = place(row);

      expect(
        position.dx + submenu.width,
        row.left,
        reason: 'its right edge should meet the panel’s left edge',
      );
      expect(
        position.dx + submenu.width,
        lessThanOrEqualTo(panelLeft),
        reason: 'and so never overlap the menu it opened from',
      );
    });

    test('lines its top up with the row', () {
      expect(place(row).dy, row.top);
    });

    test('flips upward from the row’s bottom edge', () {
      const low = Rect.fromLTRB(200, 674, 432, 700);
      expect(place(low).dy + submenu.height, low.bottom);
    });
  });

  test('the child is never asked to be bigger than the screen', () {
    final delegate = ContextMenuLayout.atPoint(Offset.zero);
    final constraints = delegate.getConstraintsForChild(
      BoxConstraints.tight(screen),
    );

    expect(constraints.maxWidth, screen.width - margin * 2);
    expect(constraints.maxHeight, screen.height - margin * 2);
    expect(constraints.minWidth, 0, reason: 'loose — menus size to content');
  });
}
