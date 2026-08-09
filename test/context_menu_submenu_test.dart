import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/context_menu/context_menu_submenu_item.dart';

/// In-memory stand-in so the HydratedCubit can be built in tests.
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

/// The submenu has to survive the pointer crossing the gap between the row and
/// the panel — the whole point of the grace period. It also has to let a miss
/// through to the menu underneath, so you can slide onto another row.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  const rowKey = Key('row');
  const panelKey = Key('panel');
  const siblingKey = Key('sibling');

  var siblingTaps = 0;

  Future<void> pump(
    WidgetTester tester, {
    Alignment alignment = Alignment.topLeft,
  }) {
    siblingTaps = 0;
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider<ThemeCubit>(
            create: (_) => ThemeCubit(),
            child: Align(
              alignment: alignment,
              child: SizedBox(
                width: 240,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ContextMenuSubmenuItem(
                      key: rowKey,
                      icon: Icons.badge_outlined,
                      label: 'Roles',
                      submenuBuilder: (_) => Container(
                        key: panelKey,
                        width: 180,
                        height: 120,
                        color: Colors.black,
                      ),
                    ),
                    GestureDetector(
                      key: siblingKey,
                      onTap: () => siblingTaps++,
                      child: Container(
                        height: 40,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<TestGesture> hoverOver(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pumpAndSettle();
    return gesture;
  }

  testWidgets('hovering the row opens the panel beside it', (tester) async {
    await pump(tester);
    expect(find.byKey(panelKey), findsNothing);

    await hoverOver(tester, find.byKey(rowKey));

    expect(find.byKey(panelKey), findsOneWidget);
    final row = tester.getRect(find.byKey(rowKey));
    final panel = tester.getRect(find.byKey(panelKey));
    expect(
      panel.left,
      greaterThanOrEqualTo(row.right),
      reason: 'the panel opens to the side, not over the row',
    );
  });

  // With the menu against the right edge there is nowhere to open into. It has
  // to go out the other side: pivoting about the row's right edge put the panel
  // straight over the menu it belongs to.
  testWidgets('opens to the left when the right is full', (tester) async {
    await pump(tester, alignment: Alignment.topRight);
    await hoverOver(tester, find.byKey(rowKey));

    final row = tester.getRect(find.byKey(rowKey));
    final panel = tester.getRect(find.byKey(panelKey));

    expect(
      panel.right,
      lessThanOrEqualTo(row.left),
      reason: 'the panel must clear the menu, not cover it',
    );
    expect(panel.left, greaterThanOrEqualTo(0));
  });

  testWidgets('moving onto the panel keeps it open', (tester) async {
    await pump(tester);
    final gesture = await hoverOver(tester, find.byKey(rowKey));

    // Leave the row — the panel is on borrowed time...
    await gesture.moveTo(const Offset(600, 500));
    await tester.pump(const Duration(milliseconds: 60));
    // ...but arriving on the panel cancels the close.
    await gesture.moveTo(tester.getCenter(find.byKey(panelKey)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(panelKey), findsOneWidget);
  });

  testWidgets('leaving both closes it', (tester) async {
    await pump(tester);
    final gesture = await hoverOver(tester, find.byKey(rowKey));

    await gesture.moveTo(const Offset(600, 500));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(panelKey), findsNothing);
  });

  testWidgets('a click outside the panel still reaches the menu', (
    tester,
  ) async {
    await pump(tester);
    await hoverOver(tester, find.byKey(rowKey));
    expect(find.byKey(panelKey), findsOneWidget);

    // The submenu's overlay fills the screen; it must not swallow this.
    await tester.tap(find.byKey(siblingKey), warnIfMissed: false);
    await tester.pump();

    expect(siblingTaps, 1);
  });
}
