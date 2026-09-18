import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/presentation/common/centered_scroll_view.dart';

const _content = Key('content');

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 800, height: 600, child: child)),
);

void main() {
  // The bug: `Center` around the scroll view shrank it to the column, and its
  // scrollbar ran down the middle of the window.
  testWidgets('the scroll view spans the space, not the column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const CenteredScrollView(
          maxWidth: 300,
          child: SizedBox(key: _content, width: 300, height: 2000),
        ),
      ),
    );

    expect(tester.getSize(find.byType(SingleChildScrollView)).width, 800);
    expect(tester.getCenter(find.byKey(_content)).dx, 400);
  });

  testWidgets('short content sits in the middle', (tester) async {
    await tester.pumpWidget(
      _host(
        const CenteredScrollView(
          child: SizedBox(key: _content, width: 100, height: 100),
        ),
      ),
    );

    expect(tester.getCenter(find.byKey(_content)), const Offset(400, 300));
  });

  testWidgets('the width cap holds on a wide window', (tester) async {
    await tester.pumpWidget(
      _host(
        const CenteredScrollView(
          maxWidth: 300,
          child: SizedBox(key: _content, width: double.infinity, height: 50),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(_content)).width, 300);
  });
}
