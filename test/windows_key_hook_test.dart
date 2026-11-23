import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
import 'package:rift/logic/ptt/mouse_button_bind.dart';
import 'package:rift/logic/ptt/windows_key_hook.dart';

/// The runner keeps one sink for `rift/ptt_keys`. A second
/// `receiveBroadcastStream` on it would take the sink over, and push-to-talk
/// or the call shortcuts would quietly stop hearing keys in the background.
void main() {
  test('only WindowsKeyHook opens the ptt channel', () {
    final opening = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains("'rift/ptt_keys'"))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    expect(opening, ['lib/logic/ptt/windows_key_hook.dart']);
  });

  group('the hooks the runner keeps in', () {
    final f9 = LogicalKeyboardKey.f9.keyId;
    final mouse4 = MouseButtonBind.keyIdFor(kBackMouseButton);
    const none = CallShortcuts();
    final muteKeys = const CallShortcuts().withKeys(
      CallShortcut.mute,
      KeyShortcut(keyId: LogicalKeyboardKey.f8.keyId),
    );

    test('none with nothing bound', () {
      expect(
        hooksWantedFor(pushToTalk: false, pushToTalkKeyId: f9, calls: none),
        (keyboard: false, mouse: false),
      );
      expect(
        hooksWantedFor(pushToTalk: true, pushToTalkKeyId: null, calls: none),
        (keyboard: false, mouse: false),
      );
    });

    test('the keyboard for a key, the mouse only for a button', () {
      expect(
        hooksWantedFor(pushToTalk: true, pushToTalkKeyId: f9, calls: none),
        (keyboard: true, mouse: false),
      );
      expect(
        hooksWantedFor(pushToTalk: true, pushToTalkKeyId: mouse4, calls: none),
        (keyboard: false, mouse: true),
      );
      expect(
        hooksWantedFor(
          pushToTalk: false,
          pushToTalkKeyId: mouse4,
          calls: muteKeys,
        ),
        (keyboard: true, mouse: false),
      );
    });
  });
}
