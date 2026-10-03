import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/ptt/mouse_button_bind.dart';
import 'package:rift/logic/ptt/win32_key_codes.dart';
import 'package:rift/logic/ptt/xdg_trigger.dart';

/// A mouse button stored as a push-to-talk keybind.
///
/// It shares the keybind's id with every key, so the one thing that must
/// never happen is the two being mistaken for each other.
void main() {
  group('MouseButtonBind', () {
    test('round-trips every button through a keybind id', () {
      for (final button in [
        kSecondaryMouseButton,
        kMiddleMouseButton,
        kBackMouseButton,
        kForwardMouseButton,
        1 << 6,
      ]) {
        expect(
          MouseButtonBind.buttonOf(MouseButtonBind.keyIdFor(button)),
          button,
        );
      }
    });

    test('never reads a key as a button', () {
      for (final key in LogicalKeyboardKey.knownLogicalKeys) {
        expect(
          MouseButtonBind.isMouse(key.keyId),
          isFalse,
          reason: key.debugName,
        );
      }
    });

    test('picks the side button, never the left one', () {
      expect(MouseButtonBind.pick(kPrimaryMouseButton), isNull);
      expect(MouseButtonBind.pick(0), isNull);
      expect(MouseButtonBind.pick(kBackMouseButton), kBackMouseButton);
      // Held while clicking: the click is not the answer.
      expect(
        MouseButtonBind.pick(kPrimaryMouseButton | kForwardMouseButton),
        kForwardMouseButton,
      );
    });

    test('names the side buttons the way games do', () {
      expect(MouseButtonBind.label(kSecondaryMouseButton), 'Right click');
      expect(MouseButtonBind.label(kMiddleMouseButton), 'Middle click');
      expect(MouseButtonBind.label(kBackMouseButton), 'Mouse 4');
      expect(MouseButtonBind.label(kForwardMouseButton), 'Mouse 5');
    });

    test('maps to the VK code the Windows hook reports', () {
      int? vk(int button) =>
          win32VkForLogicalKey(MouseButtonBind.keyIdFor(button));
      expect(vk(kSecondaryMouseButton), 0x02); // VK_RBUTTON
      expect(vk(kMiddleMouseButton), 0x04); // VK_MBUTTON
      expect(vk(kBackMouseButton), 0x05); // VK_XBUTTON1
      expect(vk(kForwardMouseButton), 0x06); // VK_XBUTTON2
      expect(vk(1 << 6), isNull);
    });

    test('is never suggested to the Linux desktop as a key', () {
      expect(
        xdgTriggerForKeyId(MouseButtonBind.keyIdFor(kBackMouseButton)),
        isNull,
      );
    });
  });
}
