import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/constants.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_button.dart';
import 'package:rift/presentation/screens/onboarding/widgets/onboarding_footer.dart';
import 'package:rift/presentation/screens/onboarding/widgets/onboarding_page.dart';

import 'helpers/memory_storage.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Scaffold(
          body: OnboardingPage(
            step: 1,
            stepLabel: 'vault',
            onBack: () {},
            footer: OnboardingFooter(
              onBack: () {},
              primary: AppButton(label: 'Create vault', onPressed: () {}),
            ),
            child: const Text('the form'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// An onboarding step on a phone is the screen, with its commit at the foot;
/// in a desktop window it is a card with Back and the commit as a pair.
void main() {
  setUpAll(() => HydratedBloc.storage = MemoryStorage());

  testWidgets('a phone pins the commit to the bottom at the thumb height', (
    tester,
  ) async {
    await _pump(tester, const Size(390, 844));

    final button = tester.getRect(find.widgetWithText(AppButton, 'Create vault'));
    expect(button.height, K.thumbCtaHeight);
    expect(button.bottom, greaterThan(844 - 40));
    // Spanning the screen, less the page's margins.
    expect(button.width, greaterThan(300));
    // Back is the arrow at the top, not a second button in the footer.
    expect(find.widgetWithText(AppButton, 'Back'), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Step 2 of 2 · vault'), findsOneWidget);
  });

  testWidgets('a desktop keeps Back and the commit as a pair in the card', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));

    final button = tester.getRect(find.widgetWithText(AppButton, 'Create vault'));
    expect(button.height, K.controlHeight);
    expect(find.widgetWithText(AppButton, 'Back'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
  });
}
