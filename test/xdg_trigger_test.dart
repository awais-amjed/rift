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
}
