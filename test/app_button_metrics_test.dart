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

    testWidgets('honours an explicit height', (tester) async {
      await _pump(tester, const AppButton(label: 'Save', height: 56));

      expect(tester.getRect(find.byType(AppButton)).height, 56);
    });

    testWidgets('matches a field, so the two line up side by side', (
      tester,
    ) async {
      expect(K.controlHeight, K.fieldHeight);
      expect(K.controlHeight, K.touchTargetMin);
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

  // A dialog's action row divides its width evenly between the buttons in it,
  // so a button is routinely handed a width it had no say in. Its label used to
  // be laid out at its natural size regardless, which put a striped overflow
  // bar down the side of the delete-channel confirmation.
  group('AppButton in a width it did not choose', () {
    testWidgets('a label too long for the space ellipsises, never overflows', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 90,
          child: AppButton(label: 'Delete channel', expanded: true),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(AppButton), findsOneWidget);
    });

    testWidgets('survives a width narrower than its own padding', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 24,
          child: AppButton(label: 'Delete channel', expanded: true),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('an icon button is no different', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 80,
          child: AppButton(
            label: 'Create channel',
            icon: Icon(Icons.add_rounded, size: 16),
            expanded: true,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('given room, the label is still shown in full', (tester) async {
      await _pump(tester, const AppButton(label: 'Delete channel'));

      final text = tester.widget<Text>(find.text('Delete channel'));
      expect(text.overflow, TextOverflow.ellipsis);
      // Wide enough for the whole label — ellipsis is a fallback, not the norm.
      expect(tester.getRect(find.byType(AppButton)).width, greaterThan(120));
    });
  });
}
