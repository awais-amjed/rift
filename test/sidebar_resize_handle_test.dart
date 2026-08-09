import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/sidebar_resize_handle.dart';

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

/// The strip between the sidebar and the content. Driven with a mouse, which
/// is what the tests use: a touch pointer swallows the first 18px into its slop
/// and would make the deltas look wrong here for a reason that has nothing to
/// do with the handle. It reports deltas while the
/// pointer is down and says when the drag is over — that separation is the
/// point: the sidebar keeps the width locally during the drag and only writes
/// it to the hydrated cubit at the end, so a drag isn't a persisted write per
/// frame.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  late List<double> deltas;
  late int ends;
  late int resets;

  Future<void> pump(WidgetTester tester) async {
    deltas = [];
    ends = 0;
    resets = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Row(
              children: [
                const SizedBox(width: 300),
                SidebarResizeHandle(
                  onDrag: deltas.add,
                  onDragEnd: () => ends++,
                  onReset: () => resets++,
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('occupies the gutter, so resizing costs no layout width', (
    tester,
  ) async {
    await pump(tester);

    expect(
      tester.getSize(find.byType(SidebarResizeHandle)).width,
      K.sidebarResizeHandleWidth,
    );
    expect(K.sidebarResizeHandleWidth, K.panelGutter);
  });

  testWidgets('a drag reports its deltas and then reports finishing', (
    tester,
  ) async {
    await pump(tester);
    final start = tester.getCenter(find.byType(SidebarResizeHandle));

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    // The move that wins the gesture arena is reported as the drag *starting*,
    // not as an update, so it is spent getting the drag going. Prime with a
    // small one and measure from there — which is also what a real mouse does,
    // a pixel at a time.
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
    deltas.clear();

    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(25, 0));
    await tester.pump();

    expect(ends, 0, reason: 'still dragging');

    await gesture.up();
    // Registering onDoubleTap means a tap-up arms a countdown; settle it or
    // the test ends with a pending timer.
    await tester.pumpAndSettle();

    expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(55, 0.5));
    expect(ends, 1);
  });

  testWidgets('dragging the other way reports negative deltas', (
    tester,
  ) async {
    await pump(tester);
    final start = tester.getCenter(find.byType(SidebarResizeHandle));

    final gesture = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(-2, 0));
    await tester.pump();
    deltas.clear();

    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(deltas.fold<double>(0, (a, b) => a + b), closeTo(-40, 0.5));
  });

  testWidgets('a double-click asks for the default width back', (
    tester,
  ) async {
    await pump(tester);
    final centre = tester.getCenter(find.byType(SidebarResizeHandle));

    await tester.tapAt(centre);
    await tester.pump(kDoubleTapMinTime);
    await tester.tapAt(centre);
    await tester.pumpAndSettle();

    expect(resets, 1);
    expect(deltas, isEmpty, reason: 'a double-click is not a drag');
  });

  testWidgets('the whole strip is grabbable, not just the painted line', (
    tester,
  ) async {
    await pump(tester);
    final rect = tester.getRect(find.byType(SidebarResizeHandle));

    // The visible line is 3px in the middle; start at the very top of the
    // strip, where nothing is painted at all.
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.top + 2),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(deltas, isNotEmpty);
    expect(ends, 1);
  });
}
