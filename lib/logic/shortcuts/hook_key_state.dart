import '../../data/classes/call_shortcuts.dart';
import '../ptt/win32_key_codes.dart';
import '../ptt/windows_key_hook.dart';

/// Which call shortcut a key from the Windows hook presses, if any.
///
/// The hook reports keys, not shortcuts, so this keeps the keys that are down
/// and works the modifiers out from them. A shortcut fires on its key going
/// down while exactly its modifiers are held, and only then: the hook reports
/// every auto-repeat as another down, and holding the keys must not flip mute
/// over and over.
///
/// A key-up the hook never saw (let go over an elevated window, which Windows
/// keeps from the hook) comes as a release from its held-key check, so a
/// modifier cannot stay held here after the finger has left it.
class HookKeyState {
  final Set<int> _down = {};

  CallShortcut? onKey(HookKey key, CallShortcuts shortcuts) {
    if (!key.down) {
      _down.remove(key.vk);
      return null;
    }
    if (!_down.add(key.vk) || _modifierVks.contains(key.vk)) return null;
    final held = (
      ctrl: _any(_ctrl),
      alt: _any(_alt),
      shift: _any(_shift),
      meta: _any(_meta),
    );
    for (final action in CallShortcut.values) {
      final keys = shortcuts[action];
      if (keys == null || win32VkForLogicalKey(keys.keyId) != key.vk) continue;
      if (keys.matchesHeld(keys.keyId, held)) return action;
    }
    return null;
  }

  bool _any(Set<int> vks) => vks.any(_down.contains);

  // The hook reports the side-specific codes; the plain ones are here in case.
  static const _shift = {0x10, 0xA0, 0xA1};
  static const _ctrl = {0x11, 0xA2, 0xA3};
  static const _alt = {0x12, 0xA4, 0xA5};
  static const _meta = {0x5B, 0x5C};
  static final _modifierVks = {..._shift, ..._ctrl, ..._alt, ..._meta};
}
