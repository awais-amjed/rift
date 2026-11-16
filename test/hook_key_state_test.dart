import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/call_shortcuts.dart';
import 'package:rift/data/classes/key_shortcut.dart';
import 'package:rift/logic/shortcuts/hook_key_state.dart';

/// Call shortcuts from the Windows hook, which reports every key and button
/// as a virtual-key code going down or up, auto-repeats included.
void main() {
  const lCtrl = 0xA2, rCtrl = 0xA3, lShift = 0xA0, rShift = 0xA1;
  const lAlt = 0xA4, m = 0x4D, f9 = 0x78;

  final shortcuts = CallShortcuts(
    mute: KeyShortcut(
      keyId: LogicalKeyboardKey.keyM.keyId,
      ctrl: true,
      shift: true,
    ),
    deafen: KeyShortcut(keyId: LogicalKeyboardKey.f9.keyId),
  );

  late HookKeyState state;
  setUp(() => state = HookKeyState());

  CallShortcut? down(int vk) =>
      state.onKey((vk: vk, down: true, byCheck: false), shortcuts);
  CallShortcut? up(int vk, {bool byCheck = false}) =>
      state.onKey((vk: vk, down: false, byCheck: byCheck), shortcuts);

  test('Ctrl+Shift+M fires once on the first down', () {
    expect(down(lCtrl), isNull);
    expect(down(lShift), isNull);
    expect(down(m), CallShortcut.mute);
    expect(down(m), isNull, reason: 'an auto-repeat is the same press');
    expect(up(m), isNull);
    expect(down(m), CallShortcut.mute, reason: 'a new press');
  });

  test('right-hand modifiers count', () {
    down(rCtrl);
    down(rShift);
    expect(down(m), CallShortcut.mute);
  });

  test('the modifiers must match exactly', () {
    down(lCtrl);
    down(lAlt);
    down(lShift);
    expect(down(m), isNull, reason: 'Ctrl+Alt+Shift+M is not Ctrl+Shift+M');
  });

  test('a release from the held-key check drops the modifier', () {
    // Ctrl let go over an elevated window: the hook never saw the key-up,
    // and its check reported it.
    down(lCtrl);
    up(lCtrl, byCheck: true);
    down(lShift);
    expect(down(m), isNull, reason: 'Ctrl is no longer held');
    up(lShift);
    expect(down(f9), CallShortcut.deafen, reason: 'F9 alone, nothing held');
  });

  test('a key with no shortcut is nothing', () {
    expect(down(0x41), isNull);
    expect(down(f9), CallShortcut.deafen);
  });

  test('a key the hook cannot report is left to the window', () {
    // A layout's own letter, like ü on a German keyboard, has no virtual-key
    // code Flutter maps back, so the hook never matches it.
    expect(HookKeyState.hears(KeyShortcut(keyId: 0xfc, ctrl: true)), isFalse);
    expect(HookKeyState.hears(shortcuts.mute!), isTrue);
  });
}
