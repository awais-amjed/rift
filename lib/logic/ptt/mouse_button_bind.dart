import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// A mouse button as a push-to-talk keybind.
///
/// Stored where a key's [LogicalKeyboardKey.keyId] goes, so a bound button is
/// one more keybind rather than a second setting that has to be kept from
/// disagreeing with the first. The id sits in a plane Flutter gives no keys
/// (it uses 0x00–0x02 and 0x11–0x18), with Flutter's own button bit
/// ([kSecondaryMouseButton], [kBackMouseButton], ...) as the value.
///
/// The left button is never one: it is how every other control is clicked,
/// so binding it would put the user on the mic with each click — and it is
/// how a capture is cancelled.
abstract final class MouseButtonBind {
  static const int _plane = 0x7700000000;

  /// The keybind id for a Flutter button bit.
  static int keyIdFor(int button) => _plane | button;

  /// The Flutter button bit a keybind id stands for, or null for a key.
  static int? buttonOf(int keyId) {
    if ((keyId & LogicalKeyboardKey.planeMask) != _plane) return null;
    final button = keyId & LogicalKeyboardKey.valueMask;
    return button == 0 ? null : button;
  }

  static bool isMouse(int keyId) => buttonOf(keyId) != null;

  /// The button a press picks, from the bits held: the lowest one that is not
  /// the left button. Null when only the left button is down.
  static int? pick(int buttons) {
    final rest = buttons & ~kPrimaryMouseButton;
    if (rest == 0) return null;
    return rest & -rest;
  }

  /// What Settings shows. Back and forward are "Mouse 4" and "Mouse 5", the
  /// names games and mouse software give the side buttons.
  static String label(int button) => switch (button) {
    kSecondaryMouseButton => 'Right click',
    kMiddleMouseButton => 'Middle click',
    _ => 'Mouse ${button.bitLength}',
  };

  /// The Win32 virtual-key code the background hook reports for a button,
  /// if Windows has one. It names five buttons; a sixth on a gaming mouse
  /// comes through its own software as a key, if at all.
  static int? win32Vk(int button) => switch (button) {
    kPrimaryMouseButton => 0x01, // VK_LBUTTON
    kSecondaryMouseButton => 0x02, // VK_RBUTTON
    kMiddleMouseButton => 0x04, // VK_MBUTTON
    kBackMouseButton => 0x05, // VK_XBUTTON1
    kForwardMouseButton => 0x06, // VK_XBUTTON2
    _ => null,
  };
}
