import 'package:flutter/services.dart';

import '../../data/classes/key_shortcut.dart';

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

/// [keys] as a suggestion to the desktop, modifiers included: `CTRL+SHIFT+m`.
///
/// Null when the key has no name the desktop would know, which leaves the
/// choice to its dialog, as for push-to-talk.
String? xdgTriggerForShortcut(KeyShortcut keys) {
  final key = xdgTriggerForKeyId(keys.keyId);
  if (key == null) return null;
  return [
    if (keys.ctrl) 'CTRL',
    if (keys.alt) 'ALT',
    if (keys.shift) 'SHIFT',
    if (keys.meta) 'LOGO',
    key,
  ].join('+');
}

/// The shortcut a desktop's description of its key names, modifiers
/// included, or null when it names something Rift cannot store.
///
/// The desktop has the last word on the key, so what it reports is what Rift
/// keeps. Desktops word it their own way: "Press Ctrl+Shift+M", "Shift+Ctrl+M"
/// or GTK's `<Control><Shift>m`, in any order.
KeyShortcut? shortcutForTriggerDescription(String description) {
  var rest = description
      .replaceFirst(RegExp('^Press ', caseSensitive: false), '')
      .trim();
  final names = <String>[];
  rest = rest.replaceAllMapped(RegExp('<([^>]+)>'), (match) {
    names.add(match.group(1)!);
    return '';
  });
  final parts = rest.split('+').map((part) => part.trim()).toList();
  final keyName = parts.removeLast();
  names.addAll(parts);
  if (keyName.isEmpty) return null;
  final key = keybindForTriggerDescription(keyName);
  if (key == null) return null;

  var ctrl = false, alt = false, shift = false, meta = false;
  for (final name in names) {
    switch (name.toLowerCase()) {
      case 'ctrl' || 'control' || 'primary':
        ctrl = true;
      case 'alt' || 'mod1':
        alt = true;
      case 'shift':
        shift = true;
      case 'super' || 'logo' || 'meta' || 'win' || 'mod4':
        meta = true;
      default:
        return null;
    }
  }
  return KeyShortcut(
    keyId: key.keyId,
    ctrl: ctrl,
    alt: alt,
    shift: shift,
    meta: meta,
  );
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
