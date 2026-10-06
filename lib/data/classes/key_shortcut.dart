import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A key pressed with modifiers, as an in-app shortcut: Ctrl+Shift+M.
///
/// The modifiers must match exactly, so Ctrl+M and Ctrl+Shift+M can be two
/// different shortcuts. Only heard while Rift's window is in front — it comes
/// from Flutter's own key events, which a window without focus does not get.
class KeyShortcut {
  /// The [LogicalKeyboardKey.keyId] of the key that is not a modifier.
  final int keyId;
  final bool ctrl;
  final bool alt;
  final bool shift;
  final bool meta;

  const KeyShortcut({
    required this.keyId,
    this.ctrl = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  /// What a key press would bind, from the modifiers held with it. Null for
  /// a modifier on its own, which is the start of a shortcut, not one.
  static KeyShortcut? fromPress(LogicalKeyboardKey key, HardwareKeyboard keys) {
    if (_modifiers.contains(key)) return null;
    return KeyShortcut(
      keyId: key.keyId,
      ctrl: keys.isControlPressed,
      alt: keys.isAltPressed,
      shift: keys.isShiftPressed,
      meta: keys.isMetaPressed,
    );
  }

  /// Whether this can be a shortcut. A key that types or moves the caret,
  /// alone or with only Shift, would fire in the middle of a message. Any
  /// other key may stand alone: F9, Page Down, Insert, a media key.
  bool get isUsable => ctrl || alt || meta || !_isTyping;

  bool get _isTyping {
    // Letters, digits, symbols and Space: every key with a character of its
    // own is in Flutter's Unicode plane.
    if (keyId & LogicalKeyboardKey.planeMask ==
        LogicalKeyboardKey.unicodePlane) {
      return true;
    }
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    return key != null && _editingKeys.contains(key);
  }

  /// Whether [key], pressed with the modifiers [keys] holds, is this one.
  bool matches(LogicalKeyboardKey key, HardwareKeyboard keys) =>
      key.keyId == keyId &&
      keys.isControlPressed == ctrl &&
      keys.isAltPressed == alt &&
      keys.isShiftPressed == shift &&
      keys.isMetaPressed == meta;

  /// "Ctrl+Shift+M", in the order the desktops write it.
  String get label => [
    if (ctrl) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    if (meta) _metaName,
    _keyName,
  ].join('+');

  String get _keyName {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (key == null) return 'Unknown key';
    final label = key.keyLabel.trim();
    if (label.isNotEmpty) return label;
    return key.debugName?.trim() ?? 'Unknown key';
  }

  static String get _metaName {
    if (kIsWeb) return 'Meta';
    if (Platform.isMacOS) return 'Cmd';
    if (Platform.isWindows) return 'Win';
    return 'Super';
  }

  static final _modifiers = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.fn,
  };

  /// What a text field uses, and the number pad, which types digits.
  /// Esc is here too: it is how picking a shortcut is cancelled.
  static final _editingKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.backspace,
    LogicalKeyboardKey.delete,
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
    LogicalKeyboardKey.numpadDecimal,
    LogicalKeyboardKey.numpadAdd,
    LogicalKeyboardKey.numpadSubtract,
    LogicalKeyboardKey.numpadMultiply,
    LogicalKeyboardKey.numpadDivide,
    LogicalKeyboardKey.numpadEqual,
    LogicalKeyboardKey.numpadComma,
    LogicalKeyboardKey.numpadEnter,
  };

  factory KeyShortcut.fromJson(Map<String, dynamic> json) => KeyShortcut(
    keyId: (json['key_id'] as num).toInt(),
    ctrl: json['ctrl'] as bool? ?? false,
    alt: json['alt'] as bool? ?? false,
    shift: json['shift'] as bool? ?? false,
    meta: json['meta'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'key_id': keyId,
    'ctrl': ctrl,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  @override
  bool operator ==(Object other) =>
      other is KeyShortcut &&
      other.keyId == keyId &&
      other.ctrl == ctrl &&
      other.alt == alt &&
      other.shift == shift &&
      other.meta == meta;

  @override
  int get hashCode => Object.hash(keyId, ctrl, alt, shift, meta);
}
