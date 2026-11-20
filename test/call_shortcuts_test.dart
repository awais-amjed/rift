import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/ptt/desktop_shortcut_settings.dart';
import 'package:rift/logic/services/host_platform.dart';
import 'package:rift/logic/shortcuts/call_shortcut_actions.dart';
import 'package:rift/logic/shortcuts/call_shortcut_listener.dart';
import 'package:rift/logic/shortcuts/linux_call_shortcuts.dart';
import 'package:rift/presentation/screens/settings/widgets/keybinds/call_shortcuts_section.dart';

import 'support/memory_storage.dart';

/// Mute and deafen shortcuts: what may be one, what matches, and picking
/// them in Settings.
void main() {
  final ctrlShiftM = KeyShortcut(
    keyId: LogicalKeyboardKey.keyM.keyId,
    ctrl: true,
    shift: true,
  );
  final ctrlShiftL = KeyShortcut(
    keyId: LogicalKeyboardKey.keyL.keyId,
    ctrl: true,
    shift: true,
  );

  group('KeyShortcut', () {
    test('reads as the desktops write it', () {
      expect(ctrlShiftM.label, 'Ctrl+Shift+M');
      expect(KeyShortcut(keyId: LogicalKeyboardKey.f9.keyId).label, 'F9');
    });

    test('a key that types is not a shortcut, with or without Shift', () {
      final m = LogicalKeyboardKey.keyM.keyId;
      expect(KeyShortcut(keyId: m).isUsable, isFalse);
      expect(KeyShortcut(keyId: m, shift: true).isUsable, isFalse);
      expect(KeyShortcut(keyId: m, ctrl: true).isUsable, isTrue);
      expect(KeyShortcut(keyId: m, alt: true).isUsable, isTrue);
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.backspace,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.numpad5,
      ]) {
        expect(KeyShortcut(keyId: key.keyId).isUsable, isFalse, reason: '$key');
      }
    });

    test('a key that types nothing may stand alone', () {
      for (final key in [
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.insert,
        LogicalKeyboardKey.pause,
        LogicalKeyboardKey.scrollLock,
        LogicalKeyboardKey.mediaPlayPause,
      ]) {
        expect(KeyShortcut(keyId: key.keyId).isUsable, isTrue, reason: '$key');
      }
      expect(
        KeyShortcut(keyId: LogicalKeyboardKey.pageDown.keyId).label,
        'Page Down',
      );
    });

    test('survives a save', () {
      expect(KeyShortcut.fromJson(ctrlShiftM.toJson()), ctrlShiftM);
    });
  });

  group('CallShortcuts', () {
    test('keys given to one action are taken from the other', () {
      final both = const CallShortcuts().withKeys(
        CallShortcut.mute,
        ctrlShiftM,
      );
      final moved = both.withKeys(CallShortcut.deafen, ctrlShiftM);
      expect(moved.mute, isNull);
      expect(moved.deafen, ctrlShiftM);
    });

    test('a saved state without them starts with none', () {
      final state = AppState.fromJson(
        const AppState().toJson()..remove('callShortcuts'),
      );
      expect(state.callShortcuts.mute, isNull);
      expect(state.callShortcuts.deafen, isNull);
    });

    test('survive a save in AppState', () {
      final saved = AppState(
        callShortcuts: CallShortcuts(deafen: ctrlShiftM),
      ).toJson();
      final state = AppState.fromJson(saved);
      expect(state.callShortcuts.deafen, ctrlShiftM);
      expect(state.callShortcuts.mute, isNull);
    });

    testWidgets('the modifiers must match exactly', (tester) async {
      final shortcuts = CallShortcuts(mute: ctrlShiftM);
      final keys = HardwareKeyboard.instance;
      CallShortcut? press() =>
          shortcuts.actionFor(LogicalKeyboardKey.keyM, keys);

      await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(press(), isNull, reason: 'Ctrl+M is not Ctrl+Shift+M');
      await simulateKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(press(), CallShortcut.mute);
      await simulateKeyDownEvent(LogicalKeyboardKey.altLeft);
      expect(press(), isNull, reason: 'nor is Ctrl+Alt+Shift+M');
      await simulateKeyUpEvent(LogicalKeyboardKey.altLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    test('an old save without leave reads as unset', () {
      final old = CallShortcuts.fromJson({
        'mute': ctrlShiftM.toJson(),
        'deafen': null,
      });
      expect(old.mute, ctrlShiftM);
      expect(old.leave, isNull);
      final saved = CallShortcuts(leave: ctrlShiftL);
      expect(CallShortcuts.fromJson(saved.toJson()).leave, ctrlShiftL);
    });

    test('one key belongs to one action, leave included', () {
      final moved = CallShortcuts(
        mute: ctrlShiftM,
      ).withKeys(CallShortcut.leave, ctrlShiftM);
      expect(moved.mute, isNull);
      expect(moved.leave, ctrlShiftM);
    });

    test('held modifiers must match exactly', () {
      final m = LogicalKeyboardKey.keyM.keyId;
      const ctrlShift = (ctrl: true, alt: false, shift: true, meta: false);
      expect(ctrlShiftM.matchesHeld(m, ctrlShift), isTrue);
      expect(
        ctrlShiftM.matchesHeld(m, (
          ctrl: true,
          alt: true,
          shift: true,
          meta: false,
        )),
        isFalse,
      );
      final shortcuts = CallShortcuts(mute: ctrlShiftM, leave: ctrlShiftL);
      expect(
        shortcuts.actionForKey(LogicalKeyboardKey.keyL.keyId, ctrlShift),
        CallShortcut.leave,
      );
      expect(shortcuts.actionForKey(m, ctrlShift), CallShortcut.mute);
    });
  });

  group('the clip shortcut', () {
    test('survives a save', () {
      final saved = CallShortcuts(clip: ctrlShiftL);
      expect(CallShortcuts.fromJson(saved.toJson()).clip, ctrlShiftL);
      expect(CallShortcuts.fromJson(saved.toJson()), saved);
    });

    test('an old save without it reads as unset', () {
      final old = CallShortcuts.fromJson({
        'mute': ctrlShiftM.toJson(),
        'deafen': null,
        'leave': null,
      });
      expect(old.clip, isNull);
      expect(old.mute, ctrlShiftM);
    });

    test('its keys are taken from mute', () {
      final moved = CallShortcuts(
        mute: ctrlShiftM,
      ).withKeys(CallShortcut.clip, ctrlShiftM);
      expect(moved.mute, isNull);
      expect(moved.clip, ctrlShiftM);
    });

    test('a press finds it', () {
      const ctrlShift = (ctrl: true, alt: false, shift: true, meta: false);
      final shortcuts = CallShortcuts(mute: ctrlShiftM, clip: ctrlShiftL);
      expect(
        shortcuts.actionForKey(LogicalKeyboardKey.keyL.keyId, ctrlShift),
        CallShortcut.clip,
      );
    });

    test('has a title and a stable desktop id', () {
      expect(callShortcutTitle(CallShortcut.clip), 'Clip the call');
      expect(portalIdFor(CallShortcut.clip), 'call-clip');
      expect(callShortcutForPortalId('call-clip'), CallShortcut.clip);
    });
  });

  group('picking in Settings', () {
    setUp(() => HydratedBloc.storage = MemoryStorage());

    Future<AppCubit> pump(WidgetTester tester) async {
      final app = AppCubit();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ThemeCubit>(create: (_) => ThemeCubit()),
            BlocProvider<AppCubit>.value(value: app),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: BlocBuilder<AppCubit, AppState>(
                builder: (_, state) => CallShortcutsSection(
                  shortcuts: state.callShortcuts,
                  desktopActions: state.desktopCallShortcuts,
                ),
              ),
            ),
          ),
        ),
      );
      return app;
    }

    Future<void> pressCtrlShiftM(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    testWidgets('keys pressed together become the shortcut', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Set keys').first);
      await tester.pump();
      expect(CallShortcutListener.capturing, isTrue);

      await pressCtrlShiftM(tester);

      expect(app.state.callShortcuts.mute, ctrlShiftM);
      expect(find.text('Ctrl+Shift+M'), findsOneWidget);
      expect(CallShortcutListener.capturing, isFalse);
    });

    testWidgets('a plain key is refused and listening goes on', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Set keys').at(1));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(app.state.callShortcuts.deafen, isNull);
      expect(
        find.text(
          'That key is for typing. Add Ctrl or Alt, or pick a key like F9.',
        ),
        findsOne,
      );

      await pressCtrlShiftM(tester);
      expect(app.state.callShortcuts.deafen, ctrlShiftM);
    });

    testWidgets('Esc cancels', (tester) async {
      final app = await pump(tester);
      await tester.tap(find.text('Set keys').first);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(app.state.callShortcuts.mute, isNull);
      expect(
        find.text('Set keys'),
        findsNWidgets(CallShortcutsSection.shownActions.length),
      );
      expect(CallShortcutListener.capturing, isFalse);
    });

    testWidgets('Clear unbinds', (tester) async {
      final app = await pump(tester);
      app.setCallShortcut(CallShortcut.mute, ctrlShiftM);
      await tester.pump();

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(app.state.callShortcuts.mute, isNull);
      expect(
        find.text('Not set'),
        findsNWidgets(CallShortcutsSection.shownActions.length),
      );
    });

    testWidgets("a desktop key Rift cannot read is shown as the desktop's", (
      tester,
    ) async {
      final app = await pump(tester);
      app.setCallShortcut(CallShortcut.mute, ctrlShiftM);
      app.setDesktopCallShortcuts({CallShortcut.mute: 'Press <Super>Print'});
      await tester.pump();

      expect(find.text('<Super>Print'), findsOneWidget);
      expect(find.text('Ctrl+Shift+M'), findsNothing);
    });

    testWidgets('Leave call has a row of its own', (tester) async {
      await pump(tester);
      expect(find.text('Leave call'), findsOneWidget);
    });

    testWidgets('Clip the call has a row where calls are clipped', (
      tester,
    ) async {
      await pump(tester);
      expect(
        find.text('Clip the call'),
        HostPlatform.clipsCalls ? findsOneWidget : findsNothing,
      );
    });

    testWidgets('they work from anywhere', (tester) async {
      await pump(tester);
      expect(
        find.text(
          'These work from anywhere, even with Rift in the background.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      "a key the desktop holds is changed in the desktop's settings",
      (tester) async {
        final app = await pump(tester);
        app.setCallShortcut(CallShortcut.mute, ctrlShiftM);
        app.setDesktopCallShortcuts({
          CallShortcut.mute: 'Press <Shift><Control>m',
        });
        await tester.pump();

        expect(find.text('Ctrl+Shift+M'), findsOneWidget);
        expect(
          find.text('Set keys'),
          findsNWidgets(CallShortcutsSection.shownActions.length - 1),
          reason: 'not for Mute',
        );
        expect(find.text('Clear'), findsOneWidget);
        if (DesktopShortcutSettings.canOpen) {
          expect(find.text('Change key'), findsOneWidget);
        } else {
          expect(
            find.text(
              "To change it, open your computer's settings and look for "
              "Rift's keyboard shortcuts.",
            ),
            findsOneWidget,
          );
        }
      },
    );
  });
}
