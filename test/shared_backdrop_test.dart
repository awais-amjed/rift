import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/presentation/common/shared_backdrop.dart';

/// The glass over a call tile shares one backdrop copy, what is painted later
/// keeps its own, and the key lasts across rebuilds: a new key each build
/// would repaint every badge every time the tile rebuilds.
void main() {
  Widget glass(String name) => SizedBox(
    key: ValueKey(name),
    width: 10,
    height: 10,
    child: BackdropFilter.grouped(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: const SizedBox.expand(),
    ),
  );

  Widget tile(int build) => Directionality(
    textDirection: TextDirection.ltr,
    child: SharedBackdrop(
      child: Column(
        children: [
          glass('name'),
          glass('quality'),
          SharedBackdrop(child: glass('later')),
          Text('$build'),
        ],
      ),
    ),
  );

  BackdropKey? keyOf(WidgetTester tester, String name) => tester
      .renderObject<RenderBackdropFilter>(
        find.descendant(
          of: find.byKey(ValueKey(name)),
          matching: find.byType(BackdropFilter),
        ),
      )
      .backdropKey;

  testWidgets('siblings share a key, a nested one has its own', (tester) async {
    await tester.pumpWidget(tile(0));
    final shared = keyOf(tester, 'name');
    expect(shared, isNotNull);
    expect(keyOf(tester, 'quality'), same(shared));
    expect(keyOf(tester, 'later'), isNotNull);
    expect(keyOf(tester, 'later'), isNot(same(shared)));
  });

  testWidgets('the keys survive a rebuild', (tester) async {
    await tester.pumpWidget(tile(0));
    final shared = keyOf(tester, 'name');
    final later = keyOf(tester, 'later');
    await tester.pumpWidget(tile(1));
    expect(keyOf(tester, 'name'), same(shared));
    expect(keyOf(tester, 'later'), same(later));
  });

  testWidgets('without one, a grouped filter shares nothing', (tester) async {
    await tester.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: glass('alone')),
    );
    expect(keyOf(tester, 'alone'), isNull);
  });
}
