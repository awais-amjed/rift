import 'package:flutter/services.dart';

/// The shortcut string the desktop portal expects for a keybind, if there is
/// one.
///
/// The portal takes a *suggestion* in the XDG shortcuts format — an XKB
/// keysym name such as `F9` or `space` — and the desktop's own dialog has the
/// final say. So this covers the keys people actually bind push-to-talk to,
/// and anything else returns null: the dialog then opens with nothing filled
/// in and the user picks the key there, which is better than a wrong guess.
String? xdgTriggerForKeyId(int keyId) {
  final named = _named[keyId];
  if (named != null) return named;

  for (var n = 1; n <= 24; n++) {
    if (_functionKeys[n - 1].keyId == keyId) return 'F$n';
  }

  // Letters and digits: their keysym name is the character itself.
  final label = LogicalKeyboardKey.findKeyByKeyId(keyId)?.keyLabel ?? '';
  if (label.length == 1 && RegExp(r'[A-Za-z0-9]').hasMatch(label)) {
    return label.toLowerCase();
  }
  return null;
}

/// The keybind a desktop's description of a key names, if it is one Rift
/// can store — the other direction of [xdgTriggerForKeyId].
///
/// The desktop owns the key once it has been granted, so Rift keeps its own
/// keybind in step with what the desktop reports; otherwise turning
/// push-to-talk off shows a stale key. Descriptions are the desktop's own
/// wording ("Press F8"), so this is forgiving about case, spacing and the
/// "Press " prefix, and gives up on combinations: those stay the desktop's
/// to show, not Rift's to store.
({int keyId, String label})? keybindForTriggerDescription(String description) {
  final name = description
      .replaceFirst(RegExp('^Press ', caseSensitive: false), '')
      .trim();
  if (name.isEmpty || name.contains('+')) return null;
  final norm = name.toLowerCase().replaceAll(RegExp(r'[\s_]'), '');

  final fn = RegExp(r'^f(\d{1,2})$').firstMatch(norm);
  if (fn != null) {
    final n = int.parse(fn.group(1)!);
    if (n < 1 || n > 24) return null;
    return (keyId: _functionKeys[n - 1].keyId, label: 'F$n');
  }
  if (RegExp(r'^[a-z0-9]$').hasMatch(norm)) {
    // Flutter's logical ids for letters and digits are the lowercase
    // character's code point.
    return (keyId: norm.codeUnitAt(0), label: norm.toUpperCase());
  }
  for (final entry in _named.entries) {
    if (entry.value.toLowerCase().replaceAll('_', '') == norm) {
      final key = LogicalKeyboardKey.findKeyByKeyId(entry.key);
      return (keyId: entry.key, label: key?.keyLabel ?? name);
    }
  }
  return null;
}

final _functionKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3, //
  LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
  LogicalKeyboardKey.f13, LogicalKeyboardKey.f14, LogicalKeyboardKey.f15,
  LogicalKeyboardKey.f16, LogicalKeyboardKey.f17, LogicalKeyboardKey.f18,
  LogicalKeyboardKey.f19, LogicalKeyboardKey.f20, LogicalKeyboardKey.f21,
  LogicalKeyboardKey.f22, LogicalKeyboardKey.f23, LogicalKeyboardKey.f24,
];

/// Keys whose keysym name is not their label.
final _named = <int, String>{
  LogicalKeyboardKey.space.keyId: 'space',
  LogicalKeyboardKey.backquote.keyId: 'grave',
  LogicalKeyboardKey.capsLock.keyId: 'Caps_Lock',
  LogicalKeyboardKey.scrollLock.keyId: 'Scroll_Lock',
  LogicalKeyboardKey.pause.keyId: 'Pause',
  LogicalKeyboardKey.insert.keyId: 'Insert',
  LogicalKeyboardKey.home.keyId: 'Home',
  LogicalKeyboardKey.end.keyId: 'End',
  LogicalKeyboardKey.pageUp.keyId: 'Page_Up',
  LogicalKeyboardKey.pageDown.keyId: 'Page_Down',
  LogicalKeyboardKey.contextMenu.keyId: 'Menu',
  LogicalKeyboardKey.tab.keyId: 'Tab',
};
