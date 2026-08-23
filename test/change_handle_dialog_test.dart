import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
import 'package:rift/presentation/screens/home/dms/widgets/central_identity_line.dart';
import 'package:rift/presentation/screens/home/dms/widgets/change_handle_dialog.dart';

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

Future<void> _pumpDialog(
  WidgetTester tester, {
  required Future<String?> Function(String) onSubmit,
  String currentHandle = 'noor',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Scaffold(
          body: ChangeHandleDialog(
            currentHandle: currentHandle,
            onSubmit: onSubmit,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The submit button, by its label rather than by position.
Finder get _submitButton => find.widgetWithText(AppButton, 'Change handle');

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<AppButton>(_submitButton).onPressed != null;

Future<void> _enter(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.pump();
}

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  group('ChangeHandleDialog', () {
    testWidgets('opens with the current handle already in the field', (
      tester,
    ) async {
      await _pumpDialog(tester, onSubmit: (_) async => null);
      // The field's own value, not its hint — the hint is the current handle
      // too, so matching on rendered text would pass on an empty field.
      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, 'noor');
    });

    testWidgets('will not submit the handle you already have', (tester) async {
      // Re-claiming your own handle is a round trip that reads like a rename
      // and changes nothing, so the button stays dark until the text differs.
      await _pumpDialog(tester, onSubmit: (_) async => null);
      expect(_submitEnabled(tester), isFalse);
    });

    testWidgets('will not submit a handle that breaks the rule', (
      tester,
    ) async {
      await _pumpDialog(tester, onSubmit: (_) async => null);
      await _enter(tester, 'no');
      expect(_submitEnabled(tester), isFalse);
    });

    testWidgets('enables once the handle is both different and valid', (
      tester,
    ) async {
      await _pumpDialog(tester, onSubmit: (_) async => null);
      await _enter(tester, 'noor_92');
      expect(_submitEnabled(tester), isTrue);
    });

    testWidgets('treats a case change as no change at all', (tester) async {
      // The directory is case-folded, so "Noor" is the handle we already hold.
      await _pumpDialog(tester, onSubmit: (_) async => null);
      await _enter(tester, 'Noor');
      expect(_submitEnabled(tester), isFalse);
    });

    testWidgets('submits the handle that was typed', (tester) async {
      String? claimed;
      await _pumpDialog(
        tester,
        onSubmit: (handle) async {
          claimed = handle;
          return null;
        },
      );
      await _enter(tester, 'noor_92');
      await tester.tap(_submitButton);
      await tester.pumpAndSettle();
      expect(claimed, 'noor_92');
    });

    testWidgets('keeps the dialog up and shows why, when the claim fails', (
      tester,
    ) async {
      await _pumpDialog(
        tester,
        onSubmit: (_) async => 'That handle is already taken',
      );
      await _enter(tester, 'noor_92');
      await tester.tap(_submitButton);
      await tester.pumpAndSettle();

      expect(find.text('That handle is already taken'), findsOneWidget);
      expect(find.byType(ChangeHandleDialog), findsOneWidget);
      // Still offering the retry, rather than stuck in its loading state.
      expect(_submitEnabled(tester), isTrue);
    });

    testWidgets('warns that the old handle stops finding you', (tester) async {
      // The consequence belongs on screen before the button, not in a toast
      // after it — by then the handle is already gone.
      await _pumpDialog(tester, onSubmit: (_) async => null);
      expect(find.textContaining('@noor'), findsWidgets);
      expect(find.textContaining('stop finding you'), findsOneWidget);
    });
  });

  group('CentralIdentityLine', () {
    Future<void> pumpLine(
      WidgetTester tester, {
      required String? handle,
      required VoidCallback onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => ThemeCubit(),
            child: Scaffold(
              body: CentralIdentityLine(handle: handle, onChangeHandle: onTap),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the handle and asks to change it when tapped', (
      tester,
    ) async {
      var asked = 0;
      await pumpLine(tester, handle: 'noor', onTap: () => asked++);

      expect(find.text('@noor'), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      expect(asked, 1);
    });

    testWidgets('offers nothing to tap before a handle is claimed', (
      tester,
    ) async {
      // The claim panel owns that case; a tap target here would be a second
      // way in that does nothing.
      await pumpLine(tester, handle: null, onTap: () {});
      expect(find.byType(InkWell), findsNothing);
      expect(find.text('central account'), findsOneWidget);
    });
  });
}
