import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/ptt/mouse_button_bind.dart';
import 'package:rift/presentation/screens/settings/widgets/voice_audio/push_to_talk_section.dart';

import 'support/memory_storage.dart';

/// Picking the push-to-talk keybind.
///
/// Any key and any mouse button but the left one: people bind the side
/// buttons on their mouse, and Esc is a key like any other. The left button is
/// the one thing that cannot be the answer, because it is how the capture is
/// cancelled — and pressing it elsewhere must not bind anything.
void main() {
  // Fresh per test: the cubit hydrates, and would start with the last
  // test's keybind.
  setUp(() => HydratedBloc.storage = MemoryStorage());

  Future<AppCubit> pump(WidgetTester tester) async {
    final app = AppCubit()..setPushToTalkEnabled(true);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
          BlocProvider<AppCubit>.value(value: app),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Somewhere else to point at, away from the section.
                const SizedBox(width: 200, height: 400),
                Expanded(
                  child: BlocBuilder<AppCubit, AppState>(
                    builder: (_, state) => PushToTalkSection(appState: state),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return app;
  }

  Future<void> pressMouse(WidgetTester tester, int buttons) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: buttons,
    );
    await gesture.down(const Offset(100, 200));
    await gesture.up();
    await tester.pump();
  }

  testWidgets('a side button pressed anywhere becomes the keybind', (
    tester,
  ) async {
    final app = await pump(tester);
    await tester.tap(find.text('Set key'));
    await tester.pump();

    await pressMouse(tester, kBackMouseButton);

    expect(
      app.state.pushToTalkKeyId,
      MouseButtonBind.keyIdFor(kBackMouseButton),
    );
    expect(app.state.pushToTalkKeyLabel, 'Mouse 4');
    expect(find.text('Mouse 4'), findsOneWidget);
    expect(find.text('Set key'), findsOneWidget, reason: 'capture ended');
  });

  testWidgets('the left button binds nothing, and Cancel stops listening', (
    tester,
  ) async {
    final app = await pump(tester);
    await tester.tap(find.text('Set key'));
    await tester.pump();

    await pressMouse(tester, kPrimaryMouseButton);
    expect(app.state.pushToTalkKeyId, isNull);
    expect(find.text('Cancel'), findsOneWidget, reason: 'still listening');

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await pressMouse(tester, kForwardMouseButton);
    expect(app.state.pushToTalkKeyId, isNull);
  });

  testWidgets('Esc is a key like any other', (tester) async {
    final app = await pump(tester);
    await tester.tap(find.text('Set key'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(app.state.pushToTalkKeyId, LogicalKeyboardKey.escape.keyId);
  });
}
