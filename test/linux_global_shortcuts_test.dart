import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/ptt/global_shortcuts_portal.dart';
import 'package:rift/logic/ptt/linux_global_shortcuts.dart';
import 'package:rift/logic/ptt/mouse_button_bind.dart';

/// GNOME keeps one saved list of shortcuts per app, and each bind replaces
/// it (checked Nov 16 with the portal: a bind of the call shortcuts alone
/// dropped push-to-talk's key, and the dialog came back for it). So Rift
/// always asks for every shortcut it has, in one list.
void main() {
  final ctrlShiftM = KeyShortcut(
    keyId: LogicalKeyboardKey.keyM.keyId,
    ctrl: true,
    shift: true,
  );
  final f8 = LogicalKeyboardKey.f8.keyId;
  const pushToTalk = PortalShortcut(
    id: 'push-to-talk',
    description: 'Push to talk',
    preferredTrigger: 'F8',
  );
  const mute = PortalShortcut(
    id: 'call-mute',
    description: 'Mute',
    preferredTrigger: 'CTRL+SHIFT+m',
  );

  test('push-to-talk and the call shortcuts go in one list', () {
    expect(
      desktopShortcutsFor(
        pushToTalk: true,
        pushToTalkKeyId: f8,
        calls: CallShortcuts(mute: ctrlShiftM),
      ),
      [pushToTalk, mute],
    );
  });

  test('push-to-talk is left out while off, unset or on a mouse button', () {
    final calls = CallShortcuts(mute: ctrlShiftM);
    for (final (on, key) in [
      (false, f8),
      (true, null),
      (true, MouseButtonBind.keyIdFor(kBackMouseButton)),
    ]) {
      expect(
        desktopShortcutsFor(pushToTalk: on, pushToTalkKeyId: key, calls: calls),
        [mute],
        reason: 'on: $on, key: $key',
      );
    }
  });

  test('nothing to ask for is an empty list', () {
    expect(
      desktopShortcutsFor(
        pushToTalk: false,
        pushToTalkKeyId: f8,
        calls: const CallShortcuts(),
      ),
      isEmpty,
    );
  });

  // GNOME 50.4 answers Cancel with 2, the same code its crashing dialog
  // helper gives (Nov 16: each Cancel brought the dialog straight back).
  group('a failed bind', () {
    test('is tried again when the desktop answered at once', () {
      expect(
        GlobalShortcutsPortal.retryBind(
          code: 2,
          waited: const Duration(milliseconds: 400),
        ),
        isTrue,
      );
    });

    test('is not tried again when a person had time to cancel', () {
      expect(
        GlobalShortcutsPortal.retryBind(
          code: 2,
          waited: const Duration(seconds: 4),
        ),
        isFalse,
      );
    });

    test('is a person saying no when it was refused or took a while', () {
      bool declined(int code, int ms) => GlobalShortcutsPortal.declinedBy(
        code: code,
        waited: Duration(milliseconds: ms),
      );
      expect(declined(1, 100), isTrue);
      expect(declined(2, 4000), isTrue);
      expect(declined(2, 400), isFalse);
      expect(declined(0, 4000), isFalse);
    });

    test('is never tried again when the person refused', () {
      expect(
        GlobalShortcutsPortal.retryBind(
          code: 1,
          waited: const Duration(milliseconds: 100),
        ),
        isFalse,
      );
    });
  });

  group('a refused list', () {
    const deafen = PortalShortcut(
      id: 'call-deafen',
      description: 'Deafen',
      preferredTrigger: 'CTRL+SHIFT+d',
    );

    test('keeps what was granted before, and sets the new one aside', () {
      final next = afterRefusal(
        asked: [pushToTalk, mute],
        granted: {'push-to-talk'},
      );
      expect(next.retry, [pushToTalk]);
      expect(next.refused, {mute});
    });

    test('with nothing granted before, there is nothing to ask again', () {
      final next = afterRefusal(asked: [pushToTalk, mute], granted: {});
      expect(next.retry, isEmpty);
      expect(next.refused, {pushToTalk, mute});
    });

    const otherMute = PortalShortcut(
      id: 'call-mute',
      description: 'Mute',
      preferredTrigger: 'CTRL+SHIFT+n',
    );

    test('a refused shortcut is not asked for again until its key changes', () {
      expect(notRefused([pushToTalk, mute, deafen], {refusalKey(mute)}), [
        pushToTalk,
        deafen,
      ]);
      expect(notRefused([otherMute], {refusalKey(mute)}), [otherMute]);
    });

    // Kept across restarts (Nov 16: one Cancel after a restart dropped every
    // key, since nothing granted was known yet, and the dialog came back at
    // every launch).
    test('remembers one refusal per shortcut, the latest key', () {
      expect(rememberRefused([refusalKey(otherMute)], [mute]), [
        refusalKey(mute),
      ]);
    });

    test('forgets a refusal once the desktop grants that shortcut', () {
      expect(
        forgetRefused(
          [refusalKey(mute), refusalKey(deafen)],
          {'call-mute', 'push-to-talk'},
        ),
        [refusalKey(deafen)],
      );
    });

    // Nov 16: a cancelled Mute kept its keys, working only in Rift's window
    // under a heading that says they work from anywhere.
    test('a cancelled call shortcut loses its keys, and is not remembered', () {
      final ctrlShiftD = KeyShortcut(
        keyId: LogicalKeyboardKey.keyD.keyId,
        ctrl: true,
        shift: true,
      );
      final next = afterDecline(
        calls: CallShortcuts(mute: ctrlShiftM, deafen: ctrlShiftD),
        refused: const [],
        declined: [mute],
      );
      expect(next.calls, CallShortcuts(deafen: ctrlShiftD));
      expect(next.refused, isEmpty);
    });

    test('a cancelled push-to-talk keeps its key and is remembered', () {
      final next = afterDecline(
        calls: CallShortcuts(mute: ctrlShiftM),
        refused: [refusalKey(mute)],
        declined: [pushToTalk, mute],
      );
      expect(next.calls, const CallShortcuts());
      expect(next.refused, [refusalKey(pushToTalk)]);
    });

    test('what was granted and refused survives a save in AppState', () {
      final saved = AppState(
        desktopShortcutsGranted: const ['push-to-talk', 'call-deafen'],
        desktopShortcutsRefused: [refusalKey(mute)],
      ).toJson();
      final state = AppState.fromJson(saved);
      expect(state.desktopShortcutsGranted, ['push-to-talk', 'call-deafen']);
      expect(state.desktopShortcutsRefused, [refusalKey(mute)]);
      final old = AppState.fromJson(
        const AppState().toJson()
          ..remove('desktopShortcutsGranted')
          ..remove('desktopShortcutsRefused'),
      );
      expect(old.desktopShortcutsGranted, isEmpty);
      expect(old.desktopShortcutsRefused, isEmpty);
    });
  });
}
