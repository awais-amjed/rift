import 'package:flutter/services.dart';

import '../../data/classes/call_shortcuts.dart';
import 'mouse_button_bind.dart';

/// One key or mouse button the Windows hook saw go down or up. [byCheck] is a
/// release the hook's held-key check decided on, not a key-up it saw.
typedef HookKey = ({int vk, bool down, bool byCheck});

/// Every key and button pressed anywhere, from the low-level hook in the
/// Windows runner (`global_key_hook.cpp`), whichever window has focus.
///
/// The one place that opens `rift/ptt_keys`. The runner keeps a single sink
/// for it, so a second `receiveBroadcastStream` takes the sink over, and the
/// first listener hears nothing more; cancelling either stops the hook for
/// both. Push-to-talk and the call shortcuts both listen here instead.
/// `test/windows_key_hook_test.dart` fails on anything else naming the
/// channel.
abstract final class WindowsKeyHook {
  static const EventChannel _channel = EventChannel('rift/ptt_keys');

  /// Opened on first listen. Broadcast: one native subscription, shared.
  static final Stream<HookKey> keys = _channel
      .receiveBroadcastStream()
      .map(_read)
      .where((key) => key != null)
      .cast<HookKey>();

  static const MethodChannel _hooks = MethodChannel('rift/ptt_hooks');

  /// Which of the runner's hooks to keep in ([hooksWantedFor]). Nothing is
  /// hooked until this says so.
  static Future<void> want({required bool keyboard, required bool mouse}) =>
      _hooks.invokeMethod<void>('want', {'keyboard': keyboard, 'mouse': mouse});

  static HookKey? _read(dynamic event) {
    if (event is! Map) return null;
    final vk = event['vk_code'];
    final down = event['is_down'];
    if (vk is! int || down is! bool) return null;
    return (vk: vk, down: down, byCheck: event['by_check'] == true);
  }
}

/// The hooks the Windows runner needs: the keyboard's while push-to-talk is on
/// a key or any call shortcut is set, the mouse's only while push-to-talk is
/// on a mouse button. Windows calls a mouse hook for every move in every app,
/// a game's included, and waits on it, so it is never in for nothing.
({bool keyboard, bool mouse}) hooksWantedFor({
  required bool pushToTalk,
  required int? pushToTalkKeyId,
  required CallShortcuts calls,
}) {
  final talkKey = pushToTalk ? pushToTalkKeyId : null;
  final onMouse = talkKey != null && MouseButtonBind.isMouse(talkKey);
  return (
    keyboard:
        (talkKey != null && !onMouse) ||
        CallShortcut.values.any((action) => calls[action] != null),
    mouse: onMouse,
  );
}
