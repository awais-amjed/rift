import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/context_menu_region.dart';

/// The delegate's arithmetic is tested next door; this is the part it can't
/// see — that the menu really lands where it was placed, and that a layout box
/// filling the overlay still lets a stray tap through to the dismiss barrier
/// behind it.
void main() {
  const menuKey = Key('menu');
  const anchorKey = Key('anchor');
  const menuWidth = 200.0;
  const menuHeight = 150.0;

  Future<void> pump(WidgetTester tester, Alignment alignment) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: alignment,
            child: const ContextMenuRegion(
              contextMenu: SizedBox(
                key: menuKey,
                width: menuWidth,
                height: menuHeight,
              ),
              // Painted, not a bare SizedBox: the region's GestureDetector
              // defers to its child, and an empty box never hit-tests.
              child: ColoredBox(
                color: Colors.blue,
                child: SizedBox(key: anchorKey, width: 120, height: 40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('opens with its top edge on the press, given room below', (
    tester,
  ) async {
    await pump(tester, Alignment.topCenter);
    final press = tester.getCenter(find.byKey(anchorKey));

    await tester.longPressAt(press);
    await tester.pumpAndSettle();

    expect(find.byKey(menuKey), findsOneWidget);
    final menu = tester.getRect(find.byKey(menuKey));
    expect(menu.top, moreOrLessEquals(press.dy, epsilon: 0.5));
  });

  // The reported bug: opening upward left a band of empty space between the
  // menu and the row that opened it, because the flip subtracted a guessed
  // height rather than the real one.
  testWidgets('opens with its bottom edge on the press, flipping upward', (
    tester,
  ) async {
    await pump(tester, Alignment.bottomCenter);
    final press = tester.getCenter(find.byKey(anchorKey));

    await tester.longPressAt(press);
    await tester.pumpAndSettle();

    final menu = tester.getRect(find.byKey(menuKey));
    expect(
      menu.bottom,
      moreOrLessEquals(press.dy, epsilon: 0.5),
      reason: 'the menu should hug the press, not float above it',
    );
    expect(menu.height, menuHeight);
  });

  testWidgets('a tap outside still reaches the dismiss barrier', (
    tester,
  ) async {
    await pump(tester, Alignment.topCenter);
    await tester.longPressAt(tester.getCenter(find.byKey(anchorKey)));
    await tester.pumpAndSettle();
    expect(find.byKey(menuKey), findsOneWidget);

    // Far from the menu — this lands on the layout box that fills the overlay,
    // which must not swallow it.
    await tester.tapAt(const Offset(20, 560));
    await tester.pumpAndSettle();

    expect(find.byKey(menuKey), findsNothing);
  });

  // An overlay entry isn't a route, so nothing closed it on Escape: the key
  // went to whatever was focused underneath and the menu stayed open.
  testWidgets('Escape closes it', (tester) async {
    await pump(tester, Alignment.topCenter);
    await tester.longPressAt(tester.getCenter(find.byKey(anchorKey)));
    await tester.pumpAndSettle();
    expect(find.byKey(menuKey), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(menuKey), findsNothing);
  });
}
