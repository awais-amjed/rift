import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/reorder_grip.dart';

/// Three rows that a finger may carry after a hold, as the server rail's are.
Future<List<String>> _pump(WidgetTester tester) async {
  final order = ['a', 'b', 'c'];
  await tester.pumpWidget(
    MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: order.length,
          onReorderItem: (from, to) =>
              setState(() => order.insert(to, order.removeAt(from))),
          itemBuilder: (context, i) => ReorderGrip(
            key: ValueKey(order[i]),
            index: i,
            touchAfterHold: true,
            child: SizedBox(height: 40, child: Text(order[i])),
          ),
        ),
      ),
    ),
  );
  return order;
}

Future<void> _carry(
  WidgetTester tester, {
  required PointerDeviceKind kind,
  Duration hold = Duration.zero,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('a')),
    kind: kind,
  );
  await tester.pump(hold);
  for (var i = 0; i < 10; i++) {
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a mouse carries a row at once', (tester) async {
    final order = await _pump(tester);
    await _carry(tester, kind: PointerDeviceKind.mouse);
    expect(order, ['b', 'c', 'a']);
  });

  testWidgets('a finger carries a row only after a hold', (tester) async {
    final order = await _pump(tester);
    await _carry(tester, kind: PointerDeviceKind.touch);
    expect(order, ['a', 'b', 'c']);

    await _carry(
      tester,
      kind: PointerDeviceKind.touch,
      hold: kLongPressTimeout + const Duration(milliseconds: 50),
    );
    expect(order, ['b', 'c', 'a']);
  });
}
