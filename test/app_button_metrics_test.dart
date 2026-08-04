import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';

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

Future<void> _pump(WidgetTester tester, Widget button) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider(
          create: (_) => ThemeCubit(),
          // Centred in a roomy box so nothing outside the button constrains
          // it — the height under test has to come from the button itself.
          child: Center(child: button),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  group('AppButton metrics', () {
    // Material pads buttons out to a 48px tap target by default, and
    // `fixedSize` would stretch them to full width. The button pins its height
    // through min/max size instead, so these guard that it actually took.
    testWidgets('stands at the control height by default', (tester) async {
      await _pump(tester, const AppButton(label: 'Primary'));

      final rect = tester.getRect(find.byType(AppButton));
      expect(rect.height, K.controlHeight);
    });

    testWidgets('honours a taller height for dialog footers', (tester) async {
      await _pump(
        tester,
        const AppButton(label: 'Save', height: K.fieldHeight),
      );

      expect(tester.getRect(find.byType(AppButton)).height, K.fieldHeight);
    });

    testWidgets('sizes to its label rather than filling the row', (
      tester,
    ) async {
      await _pump(tester, const AppButton(label: 'OK'));

      final rect = tester.getRect(find.byType(AppButton));
      expect(rect.width, lessThan(200));
    });

    testWidgets('expanded fills the width but keeps its height', (
      tester,
    ) async {
      await _pump(tester, const AppButton(label: 'Create', expanded: true));

      final rect = tester.getRect(find.byType(AppButton));
      expect(rect.height, K.controlHeight);
      expect(rect.width, 800);
    });

    testWidgets('a disabled button keeps the same footprint', (tester) async {
      await _pump(tester, const AppButton(label: 'Primary', onPressed: null));

      expect(tester.getRect(find.byType(AppButton)).height, K.controlHeight);
    });
  });
}
