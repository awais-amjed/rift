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
