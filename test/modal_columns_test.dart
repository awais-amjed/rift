import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/modal_columns.dart';

/// In-memory stand-in so [ThemeCubit] (a HydratedCubit) can be built in tests.
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

/// The server settings form has two halves that used to run down the page and
/// scroll on a window with several hundred spare pixels either side. Side by
/// side they fit — but only while there is room for both, and only if the rule
/// between them can find the height of the taller one.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    double leftHeight = 300,
    double rightHeight = 400,
  }) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: width,
                child: ModalColumns(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: leftHeight, child: const Text('left')),
                      ],
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: rightHeight,
                          child: const Text('right'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a wide modal puts the sections beside each other', (
    tester,
  ) async {
    await pump(tester, width: 720);

    final left = tester.getRect(find.text('left'));
    final right = tester.getRect(find.text('right'));

    expect(right.left, greaterThan(left.right), reason: 'not stacked');
    expect(left.top, right.top, reason: 'both start at the top');
    expect(find.byType(VerticalDivider), findsOneWidget);
  });

  testWidgets('the rule runs the height of the taller section', (tester) async {
    await pump(tester, width: 720, leftHeight: 300, rightHeight: 400);

    // Not just decoration: this is what [IntrinsicHeight] is buying, and
    // without it the rule collapses to nothing in an unbounded column.
    expect(tester.getSize(find.byType(VerticalDivider)).height, 400);
  });

  testWidgets('a narrow modal stacks them instead of cramping the fields', (
    tester,
  ) async {
    await pump(tester, width: 420);

    final left = tester.getRect(find.text('left'));
    final right = tester.getRect(find.text('right'));

    expect(right.top, greaterThan(left.bottom), reason: 'not side by side');
    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('the threshold counts the gutter, not just the columns', (
    tester,
  ) async {
    // Two 300px columns need more than 600px, because the rule and its
    // gutters sit between them.
    await pump(tester, width: 620);
    expect(find.byType(VerticalDivider), findsNothing);

    await pump(tester, width: 660);
    expect(find.byType(VerticalDivider), findsOneWidget);
  });
}
