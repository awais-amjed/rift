import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/edge_tab.dart';

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// The tab that brings a hidden side panel back — used on both edges now.
///
/// The left sidebar used to open on hover, which meant a pointer crossing the
/// window edge on its way somewhere threw a panel over the content. The tab is
/// the whole affordance, and hovering it must do no more than light it up.
///
/// The panels themselves need most of the app's cubits to build, so these
/// drive the tab: the piece that decides whether anything opens at all.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  late int taps;

  Future<void> pump(WidgetTester tester) async {
    taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Align(
              alignment: Alignment.topLeft,
              child: EdgeTab(
                side: EdgeTabSide.left,
                tooltip: 'Show sidebar',
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hovering the tab does not open anything', (tester) async {
    await pump(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(EdgeTab)));
    await tester.pumpAndSettle();

    expect(taps, 0, reason: 'hover is not a request to open');
  });

  testWidgets('hovering does widen it, so it reads as pressable', (
    tester,
  ) async {
    await pump(tester);
    final resting = tester.getSize(find.byType(EdgeTab)).width;

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(EdgeTab)));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(EdgeTab)).width, greaterThan(resting));
  });

  testWidgets('clicking it asks to open, once per click', (tester) async {
    await pump(tester);

    await tester.tap(find.byType(EdgeTab));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.tap(find.byType(EdgeTab));
    await tester.pumpAndSettle();
    expect(taps, 2);
  });

  testWidgets('it is big enough to hit without aiming', (tester) async {
    await pump(tester);

    final size = tester.getSize(find.byType(EdgeTab));
    // The old affordance was a 4px-wide nub. A pointer target that thin is one
    // you have to aim at.
    expect(size.width, greaterThanOrEqualTo(16));
    expect(size.height, greaterThanOrEqualTo(44));
  });
}
