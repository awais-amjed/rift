import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
import 'package:rift/logic/ptt/global_shortcuts_portal.dart';
import 'package:rift/logic/shortcuts/linux_call_shortcuts.dart';

/// What Rift asks the Linux desktop for, and what it keeps of the answer.
void main() {
  final ctrlShiftM = KeyShortcut(
    keyId: LogicalKeyboardKey.keyM.keyId,
    ctrl: true,
    shift: true,
  );
  final ctrlShiftP = KeyShortcut(
    keyId: LogicalKeyboardKey.keyP.keyId,
    ctrl: true,
    shift: true,
  );
  final f9 = KeyShortcut(keyId: LogicalKeyboardKey.f9.keyId);

  test('only set actions are offered, with their combination', () {
    expect(portalShortcutsFor(CallShortcuts(mute: ctrlShiftM)), const [
      PortalShortcut(
        id: 'call-mute',
        description: 'Mute',
        preferredTrigger: 'CTRL+SHIFT+m',
      ),
    ]);
    expect(
      portalShortcutsFor(CallShortcuts(deafen: f9, leave: ctrlShiftP)),
      const [
        PortalShortcut(
          id: 'call-deafen',
          description: 'Deafen',
          preferredTrigger: 'F9',
        ),
        PortalShortcut(
          id: 'call-leave',
          description: 'Leave call',
          preferredTrigger: 'CTRL+SHIFT+p',
        ),
      ],
    );
  });

  test('nothing set offers nothing, so the session closes', () {
    expect(portalShortcutsFor(const CallShortcuts()), isEmpty);
  });

  test('the id names the action, both ways', () {
    for (final action in CallShortcut.values) {
      expect(callShortcutForPortalId(portalIdFor(action)), action);
    }
    expect(callShortcutForPortalId('push-to-talk'), isNull);
  });

  group('adoptDesktopKeys', () {
    test("the desktop's key becomes the stored one", () {
      final adopted = adoptDesktopKeys(CallShortcuts(mute: ctrlShiftM), {
        'call-mute': 'Press Shift+Ctrl+P',
      });
      expect(adopted.mute, ctrlShiftP);
    });

    test('a key that cannot be read, or none, keeps the stored one', () {
      final stored = CallShortcuts(mute: ctrlShiftM, deafen: f9);
      expect(
        adoptDesktopKeys(stored, {'call-mute': 'Hyper+M', 'call-deafen': ''}),
        stored,
      );
    });

    test('a key the desktop gave another action moves to this one', () {
      final adopted = adoptDesktopKeys(
        CallShortcuts(mute: ctrlShiftM, deafen: ctrlShiftP),
        {'call-mute': 'Ctrl+Shift+P'},
      );
      expect(adopted.mute, ctrlShiftP);
      expect(adopted.deafen, isNull);
    });
  });

  test('which actions the desktop delivers', () {
    expect(deliveredActions({'call-mute': 'Press F9', 'call-deafen': ''}), {
      CallShortcut.mute,
    });
  });
}
