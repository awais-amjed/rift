import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/screens/onboarding/widgets/onboarding_page.dart';

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

/// A phone's sign-in step pins its button to the bottom of the screen, where
/// a thumb is. With the keyboard up, pinned meant riding up on the keyboard
/// over the form, so the button goes back under the fields until it closes.
void main() {
  setUpAll(() => HydratedBloc.storage = _MemoryStorage());

  final button = find.widgetWithText(FilledButton, 'Sign in');
  final inScroll = find.descendant(
    of: find.byType(SingleChildScrollView),
    matching: button,
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      BlocProvider(
        create: (_) => ThemeCubit(),
        child: MaterialApp(
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: OnboardingPage(
              step: 1,
              stepLabel: 'Account',
              onBack: () {},
              footer: FilledButton(
                onPressed: () {},
                child: const Text('Sign in'),
              ),
              child: const TextField(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the button is pinned at the foot while nobody is typing', (
    tester,
  ) async {
    await pump(tester);
    expect(button, findsOneWidget);
    expect(inScroll, findsNothing);
    expect(tester.getBottomLeft(button).dy, greaterThan(844 - 100));
  });

  testWidgets('with the keyboard up it goes under the form, keeping focus', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pumpAndSettle();
    expect(inScroll, findsOneWidget);
    // The field typed into was not built afresh by the move.
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(inScroll, findsNothing);
    expect(button, findsOneWidget);
  });
}
