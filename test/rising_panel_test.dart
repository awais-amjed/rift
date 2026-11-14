import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/presentation/common/context_menu/context_menu_watcher.dart';
import 'package:rift/presentation/common/rising_panel.dart';

/// The volume's standing track: whatever fades its controls must hear it
/// open and close, and it must not close under a drag that has left it —
/// the stream's controls faded mid-drag, and took the speaker with them.
void main() {
  testWidgets('tells the watcher, and holds through a drag', (tester) async {
    var opened = 0;
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ContextMenuWatcher(
          onOpened: () => opened++,
          onClosed: () => closed++,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: RisingPanel(
              anchor: const SizedBox(key: Key('anchor'), width: 30, height: 30),
              panel: (_) =>
                  const SizedBox(key: Key('panel'), width: 30, height: 100),
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byKey(const Key('anchor'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);
    expect((opened, closed), (1, 0));

    // Up onto the panel, pressed, and dragged off it: still up.
    final panel = tester.getCenter(find.byKey(const Key('panel')));
    expect(
      panel.dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('anchor'))).dy),
    );
    await mouse.moveTo(panel);
    await mouse.down(panel);
    await mouse.moveTo(Offset.zero);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsOneWidget);
    expect(closed, 0);

    // Let go away from it: it goes a moment later.
    await mouse.up();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('panel')), findsNothing);
    expect((opened, closed), (1, 1));
    await mouse.removePointer();
  });
}
