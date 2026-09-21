import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/ptt/xdg_trigger.dart';

void main() {
  test('function keys', () {
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.f1.keyId), 'F1');
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.f9.keyId), 'F9');
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.f24.keyId), 'F24');
  });

  test('letters and digits are their lowercase character', () {
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.keyV.keyId), 'v');
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.digit4.keyId), '4');
  });

  test('named keys use their keysym name', () {
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.backquote.keyId), 'grave');
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.capsLock.keyId), 'Caps_Lock');
  });

  test('keys without a mapping leave the choice to the desktop', () {
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.shiftLeft.keyId), isNull);
    expect(xdgTriggerForKeyId(LogicalKeyboardKey.semicolon.keyId), isNull);
  });

  group('keybindForTriggerDescription', () {
    test('function keys, with or without the prefix', () {
      expect(keybindForTriggerDescription('Press F8'), (
        keyId: LogicalKeyboardKey.f8.keyId,
        label: 'F8',
      ));
      expect(
        keybindForTriggerDescription('f12')?.keyId,
        LogicalKeyboardKey.f12.keyId,
      );
    });

    test('letters and digits', () {
      expect(keybindForTriggerDescription('Press G'), (
        keyId: LogicalKeyboardKey.keyG.keyId,
        label: 'G',
      ));
      expect(
        keybindForTriggerDescription('Press 4')?.keyId,
        LogicalKeyboardKey.digit4.keyId,
      );
    });

    test('named keys, however the desktop spaces them', () {
      expect(
        keybindForTriggerDescription('Press Page Up')?.keyId,
        LogicalKeyboardKey.pageUp.keyId,
      );
      expect(
        keybindForTriggerDescription('Press Caps_Lock')?.keyId,
        LogicalKeyboardKey.capsLock.keyId,
      );
    });

    test('round-trips what Rift suggests', () {
      for (final key in [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.home,
      ]) {
        final trigger = xdgTriggerForKeyId(key.keyId)!;
        expect(keybindForTriggerDescription(trigger)?.keyId, key.keyId);
      }
    });

    test('combinations and nonsense are left to the desktop', () {
      expect(keybindForTriggerDescription('Press Ctrl+G'), isNull);
      expect(keybindForTriggerDescription('Press F99'), isNull);
      expect(keybindForTriggerDescription(''), isNull);
    });
  });
}
