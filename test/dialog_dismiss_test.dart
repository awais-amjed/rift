import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/show_custom_dialog.dart';

/// Opens a small dialog holding [child] from a bare app, and waits for it.
Future<void> _open(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCustomDialog<void>(
              context: context,
              build: (_) => Center(
                child: SizedBox(width: 200, height: 120, child: child),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// A click well clear of the dialog, on the barrier.
Future<void> _clickOutside(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a click outside closes a dialog, as Escape does', (
    tester,
  ) async {
    await _open(tester, const Material(child: Text('dialog')));
    expect(find.text('dialog'), findsOneWidget);

    // A click on the dialog itself leaves it open.
    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsOneWidget);

    await _clickOutside(tester);
    expect(find.text('dialog'), findsNothing);
  });

  testWidgets('a dialog that holds itself open is not closed by a click', (
    tester,
  ) async {
    // As a dialog does while a save is under way.
    await _open(
      tester,
      const PopScope(canPop: false, child: Material(child: Text('saving'))),
    );
    await _clickOutside(tester);
    expect(find.text('saving'), findsOneWidget);
  });
}
