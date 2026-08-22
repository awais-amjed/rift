import 'package:flutter/services.dart';

/// Maps a Flutter logical key to the Win32 Virtual Key code the background
/// keyboard hook reports for it.
///
/// The keybind picker stores whatever [LogicalKeyboardKey.keyId] the user
/// pressed, but the WH_KEYBOARD_LL hook in the Windows runner only knows VK
/// codes. A key missing from this table can never fire while the app is in the
/// background, because there is nothing to compare the hook's code against —
/// so it has to cover every key the picker will accept, which is all of them.
///
/// **This is [kWindowsToLogicalKey] turned around, not a table of our own.**
/// It used to be hand-written hex, and three of its entries matched no key at
/// all: F1–F24 and the numpad digits were looked up in ranges 0x7a0 and 0x200
/// below where Flutter actually puts them, and Enter, Tab, Escape and
/// Backspace were looked up at their bare ASCII values rather than in
/// Flutter's non-printable plane — so all of those, the two most obvious
/// push-to-talk keys among them, silently did nothing in the background.
/// Reading Flutter's own generated map instead means the ids can never drift
/// from the SDK again, and the whole 155-entry keyboard comes for free.
///
/// Which character a key produces still moves with the layout — Windows keys
/// punctuation on VK_OEM_* codes for the *physical* key, so a keybind shown as
/// `;` fires whatever that key types under another layout.
int? win32VkForLogicalKey(int keyId) => _vkByKeyId[keyId];

/// Real keys that [kWindowsToLogicalKey] happens not to list.
///
/// Not `const`: [LogicalKeyboardKey] overrides `==`, which a constant map key
/// may not do.
final _supplement = <LogicalKeyboardKey, int>{
  // The extra key on a 102-key ISO board, between left shift and Z.
  LogicalKeyboardKey.intlBackslash: 0xE2, // VK_OEM_102
  // The other half of the Japanese pair either side of the space bar.
  // Flutter's map has `convert` but not this one.
  LogicalKeyboardKey.nonConvert: 0x1D, // VK_NONCONVERT
  // Media-row keys Flutter's map skips while listing their neighbours.
  LogicalKeyboardKey.mediaTrackNext: 0xB0, // VK_MEDIA_NEXT_TRACK
  LogicalKeyboardKey.mediaTrackPrevious: 0xB1, // VK_MEDIA_PREV_TRACK
  LogicalKeyboardKey.launchMediaPlayer: 0xB5, // VK_LAUNCH_MEDIA_SELECT
  LogicalKeyboardKey.launchApplication1: 0xB6, // VK_LAUNCH_APP1
  LogicalKeyboardKey.launchApplication2: 0xB7, // VK_LAUNCH_APP2
  // Numpad Enter shares VK_RETURN with the main Enter, so binding either one
  // makes both work. Telling them apart needs the extended-key flag, which the
  // hook does not send — better than the key doing nothing at all.
  LogicalKeyboardKey.numpadEnter: 0x0D, // VK_RETURN
};

/// [kWindowsToLogicalKey] inverted, then supplemented.
///
/// Two logical keys have two VKs each: `shiftLeft` is listed under both
/// VK_SHIFT (0x10) and VK_LSHIFT (0xA0), and `controlLeft` under both
/// VK_CONTROL (0x11) and VK_LCONTROL (0xA2). The higher code wins, because a
/// low-level hook always reports the side-specific one — matching the way
/// Flutter itself distinguishes left from right, so both halves of a keybind
/// agree on which key was meant.
final Map<int, int> _vkByKeyId = () {
  final byKeyId = <int, int>{};
  for (final entry in kWindowsToLogicalKey.entries) {
    final keyId = entry.value.keyId;
    final existing = byKeyId[keyId];
    if (existing == null || entry.key > existing) byKeyId[keyId] = entry.key;
  }
  for (final entry in _supplement.entries) {
    byKeyId[entry.key.keyId] = entry.value;
  }
  return byKeyId;
}();
