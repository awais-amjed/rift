import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/app_dropdown.dart';
import 'package:rift/presentation/common/refresh_button.dart';
import 'package:rift/presentation/theme/app_motion.dart';

/// A press that seemed to do nothing: the list came back unchanged at once,
/// so the arrow turning is what says it was heard.

Widget themed(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [ThemeState()]),
  home: Scaffold(body: Center(child: child)),
);

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: find.byType(RefreshButton),
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

void main() {
  dropdownTests();

  testWidgets('a list that comes back at once still shows a whole turn', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      themed(
        RefreshButton(
          onRefresh: () async {
            calls++;
          },
        ),
      ),
    );
    expect(_turns(tester), 0);

    await tester.tap(find.byType(RefreshButton));
    await tester.pump();
    await tester.pump(AppMotion.turn ~/ 2);
    expect(_turns(tester), inExclusiveRange(0, 1), reason: 'mid-turn');

    // A second press while it turns is the same press.
    await tester.tap(find.byType(RefreshButton));
    await tester.pump(AppMotion.turn);
    expect(_turns(tester), 1);
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('it goes on turning until a slow list comes back', (
    tester,
  ) async {
    final load = Completer<void>();
    await tester.pumpWidget(
      themed(RefreshButton(onRefresh: () => load.future)),
    );

    await tester.tap(find.byType(RefreshButton));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(AppMotion.turn);
    }
    expect(tester.hasRunningAnimations, isTrue);

    load.complete();
    await tester.pump(AppMotion.turn);
    await tester.pump(AppMotion.turn);
    expect(tester.hasRunningAnimations, isFalse);
  });
}

class _Apps extends StatefulWidget {
  const _Apps();

  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  var apps = ['Firefox'];
  String? picked;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 400,
    child: AppDropdown<String?>(
      value: picked,
      hint: 'All apps',
      options: [
        for (final app in apps) AppDropdownOption(value: app, label: app),
      ],
      onChanged: (app) => setState(() => picked = app),
      onRefresh: () async => setState(() => apps = [...apps, 'Spotify']),
    ),
  );
}

void dropdownTests() {
  testWidgets('refresh with the list open keeps it open, with the new list', (
    tester,
  ) async {
    await tester.pumpWidget(themed(const _Apps()));
    await tester.tap(find.text('All apps'));
    await tester.pumpAndSettle();
    expect(find.text('Firefox'), findsOneWidget);
    expect(find.text('Spotify'), findsNothing);

    await tester.tap(find.byType(RefreshButton));
    await tester.pumpAndSettle();
    expect(find.text('Firefox'), findsOneWidget, reason: 'still open');
    expect(find.text('Spotify'), findsOneWidget, reason: 'the new list');

    // A click anywhere else still closes it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Spotify'), findsNothing);
  });
}
