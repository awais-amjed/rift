import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
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
}
