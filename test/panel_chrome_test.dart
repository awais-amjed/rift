import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/data/enums/layout_mode.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_panel.dart';

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

/// The island look is the most expensive decoration in the design and the
/// first thing a phone cannot afford. Both halves need holding: it has to go
/// on a small screen, and it has to stay everywhere else — a panel that
/// quietly lost its border on a desktop would be a redesign nobody asked for.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  Future<BoxDecoration> panelDecoration(
    WidgetTester tester,
    double windowWidth, {
    BorderRadius? borderRadius,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: Size(windowWidth, 800),
          // A notch and a home indicator, so the inset behaviour is visible.
          padding: const EdgeInsets.only(top: 40, bottom: 24),
        ),
        child: MaterialApp(
          home: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Scaffold(
              // Expanded, because a panel shrink-wraps: in the app it is
              // always inside a Row or an Expanded that hands it the screen.
              body: SizedBox.expand(
                child: AppPanel(
                  borderRadius: borderRadius,
                  child: const Align(
                    alignment: Alignment.topLeft,
                    child: Text('body'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(AppPanel),
            matching: find.byType(Container),
          )
          .first,
    );
    return container.decoration! as BoxDecoration;
  }

  testWidgets('a phone gets a surface, not an island', (tester) async {
    final d = await panelDecoration(tester, 390);
    expect(
      d.borderRadius,
      BorderRadius.zero,
      reason:
          'rounded at the corners '
          'of a screen that has its own radius',
    );
    expect(d.border, isNull, reason: 'a hairline against the screen edge');
  });

  testWidgets('a desktop keeps the island chrome', (tester) async {
    final d = await panelDecoration(tester, 1400);
    expect(d.borderRadius, BorderRadius.circular(K.radiusPanel));
    expect(d.border, isNotNull);
  });

  testWidgets('a drawer may round only the edge facing the content', (
    tester,
  ) async {
    const drawer = BorderRadius.horizontal(right: Radius.circular(16));
    expect(
      await panelDecoration(tester, 390, borderRadius: drawer),
      isA<BoxDecoration>().having((d) => d.borderRadius, 'radius', drawer),
    );
  });

  testWidgets('the surface runs under the cutouts and the content does not', (
    tester,
  ) async {
    // The whole point of moving the inset in here: the panel paints edge to
    // edge while its child stops short of the status bar. Insetting the
    // workspace instead left a band of backdrop at each end of the screen.
    await panelDecoration(tester, 390);
    // Against the real test surface, not the reported MediaQuery size — the
    // two differ, and it is the surface the panel is actually laid out in.
    expect(
      tester.getSize(find.byType(AppPanel)).height,
      tester.getSize(find.byType(Scaffold)).height,
      reason: 'the panel should reach both ends of the screen',
    );
    expect(
      tester.getTopLeft(find.text('body')).dy,
      greaterThanOrEqualTo(40),
      reason: 'the content should clear the notch',
    );
  });

  testWidgets('a docked panel does not inset its child twice', (tester) async {
    // The workspace already holds the islands clear of everything, so the
    // only thing between the panel's top and its child is the 1px border.
    await panelDecoration(tester, 1400);
    expect(tester.getTopLeft(find.text('body')).dy, lessThan(40));
  });

  test('the gutter is what separates the two cases', () {
    expect(LayoutMode.compact.panelsAreIslands, isFalse);
    expect(LayoutMode.compact.panelGutter, 0);
    for (final mode in [LayoutMode.medium, LayoutMode.expanded]) {
      expect(mode.panelsAreIslands, isTrue);
      expect(mode.panelGutter, K.panelGutter);
    }
  });
}
