import 'package:flutter/services.dart';

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

  static HookKey? _read(dynamic event) {
    if (event is! Map) return null;
    final vk = event['vk_code'];
    final down = event['is_down'];
    if (vk is! int || down is! bool) return null;
    return (vk: vk, down: down, byCheck: event['by_check'] == true);
  }
}
