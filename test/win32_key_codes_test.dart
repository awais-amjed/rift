import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/ptt/win32_key_codes.dart';

/// The guard on background push-to-talk.
///
/// Three ranges in the old hand-written table used ids that belong to no key
/// at all — F1–F24 and the numpad digits were looked up 0x7a0 and 0x200 below
/// where Flutter puts them, and Enter/Tab/Escape/Backspace were looked up at
/// their bare ASCII values instead of in Flutter's non-printable plane. Every
/// one of those is a key somebody would plausibly bind to push-to-talk, and
/// all of them quietly did nothing while the app was in the background.
///
/// Nothing here hard-codes a Flutter id: every case asks [LogicalKeyboardKey]
/// for it, so a table that drifts from the SDK fails rather than going silent.
void main() {
  int? vkFor(LogicalKeyboardKey key) => win32VkForLogicalKey(key.keyId);

  group('win32VkForLogicalKey', () {
    test('maps letters and digits', () {
      expect(vkFor(LogicalKeyboardKey.keyA), 0x41); // VK_A
      expect(vkFor(LogicalKeyboardKey.keyQ), 0x51);
      expect(vkFor(LogicalKeyboardKey.keyZ), 0x5A);
      expect(vkFor(LogicalKeyboardKey.digit0), 0x30);
      expect(vkFor(LogicalKeyboardKey.digit9), 0x39);
    });

    test('maps every function key to VK_F1–VK_F24', () {
      // The old range started at 0x100000063; f1 is really 0x100000801.
      expect(vkFor(LogicalKeyboardKey.f1), 0x70);
      expect(vkFor(LogicalKeyboardKey.f4), 0x73);
      expect(vkFor(LogicalKeyboardKey.f12), 0x7B);
      expect(vkFor(LogicalKeyboardKey.f24), 0x87);
    });

    test('maps every numpad digit to VK_NUMPAD0–VK_NUMPAD9', () {
      // The old range started at 0x200000030; numpad0 is really 0x200000230.
      expect(vkFor(LogicalKeyboardKey.numpad0), 0x60);
      expect(vkFor(LogicalKeyboardKey.numpad5), 0x65);
      expect(vkFor(LogicalKeyboardKey.numpad9), 0x69);
    });

    test('maps the whitespace and editing keys, which are not their own '
        'ASCII values', () {
      expect(vkFor(LogicalKeyboardKey.backspace), 0x08); // VK_BACK
      expect(vkFor(LogicalKeyboardKey.tab), 0x09);
      expect(vkFor(LogicalKeyboardKey.enter), 0x0D);
      expect(vkFor(LogicalKeyboardKey.escape), 0x1B);
      expect(vkFor(LogicalKeyboardKey.space), 0x20);
      expect(vkFor(LogicalKeyboardKey.delete), 0x2E);
      expect(vkFor(LogicalKeyboardKey.insert), 0x2D);
    });

    test('maps navigation keys, which used to be shuffled among '
        'themselves', () {
      expect(vkFor(LogicalKeyboardKey.home), 0x24); // VK_HOME
      expect(vkFor(LogicalKeyboardKey.end), 0x23); // VK_END
      expect(vkFor(LogicalKeyboardKey.pageUp), 0x21); // VK_PRIOR
      expect(vkFor(LogicalKeyboardKey.pageDown), 0x22); // VK_NEXT
      expect(vkFor(LogicalKeyboardKey.arrowUp), 0x26);
      expect(vkFor(LogicalKeyboardKey.arrowDown), 0x28);
      expect(vkFor(LogicalKeyboardKey.arrowLeft), 0x25);
      expect(vkFor(LogicalKeyboardKey.arrowRight), 0x27);
    });

    test('prefers the side-specific modifier VKs the hook reports', () {
      // Flutter's map lists shiftLeft and controlLeft twice, once under the
      // generic VK_SHIFT / VK_CONTROL. A low-level hook never sends those, so
      // picking one over the other decides whether the keybind works at all.
      expect(vkFor(LogicalKeyboardKey.shiftLeft), 0xA0); // VK_LSHIFT, not 0x10
      expect(vkFor(LogicalKeyboardKey.shiftRight), 0xA1);
      expect(vkFor(LogicalKeyboardKey.controlLeft), 0xA2); // not 0x11
      expect(vkFor(LogicalKeyboardKey.controlRight), 0xA3);
      expect(vkFor(LogicalKeyboardKey.altLeft), 0xA4);
      expect(vkFor(LogicalKeyboardKey.altRight), 0xA5);
      expect(vkFor(LogicalKeyboardKey.metaLeft), 0x5B); // VK_LWIN
      expect(vkFor(LogicalKeyboardKey.metaRight), 0x5C);
    });

    test('maps US punctuation to the VK_OEM_* codes', () {
      expect(vkFor(LogicalKeyboardKey.backquote), 0xC0); // VK_OEM_3
      expect(vkFor(LogicalKeyboardKey.semicolon), 0xBA);
      expect(vkFor(LogicalKeyboardKey.slash), 0xBF);
      expect(vkFor(LogicalKeyboardKey.bracketLeft), 0xDB);
      expect(vkFor(LogicalKeyboardKey.quote), 0xDE);
    });

    test('covers every key a Windows keyboard can send through the hook', () {
      // Walking `knownLogicalKeys` would fail on TV remotes and gamepads, so
      // this is the inverse: everything physically on a PC keyboard, spelled
      // out, because any gap here is a keybind that silently does nothing.
      final everyPhysicalKey = <LogicalKeyboardKey>[
        // Punctuation is named rather than derived from characters: the
        // apostrophe key is `LogicalKeyboardKey.quote`, whose id is `"`.
        LogicalKeyboardKey.backquote, LogicalKeyboardKey.minus,
        LogicalKeyboardKey.equal, LogicalKeyboardKey.bracketLeft,
        LogicalKeyboardKey.bracketRight, LogicalKeyboardKey.backslash,
        LogicalKeyboardKey.semicolon, LogicalKeyboardKey.quote,
        LogicalKeyboardKey.comma, LogicalKeyboardKey.period,
        LogicalKeyboardKey.slash, LogicalKeyboardKey.intlBackslash,
        LogicalKeyboardKey.space, LogicalKeyboardKey.enter,
        LogicalKeyboardKey.tab, LogicalKeyboardKey.escape,
        LogicalKeyboardKey.backspace, LogicalKeyboardKey.delete,
        LogicalKeyboardKey.insert, LogicalKeyboardKey.home,
        LogicalKeyboardKey.end, LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown, LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.capsLock,
        LogicalKeyboardKey.numLock, LogicalKeyboardKey.scrollLock,
        LogicalKeyboardKey.printScreen, LogicalKeyboardKey.pause,
        LogicalKeyboardKey.contextMenu, LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.controlRight, LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.shiftRight, LogicalKeyboardKey.altLeft,
        LogicalKeyboardKey.altRight, LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.metaRight, LogicalKeyboardKey.numpadEnter,
        LogicalKeyboardKey.numpadAdd, LogicalKeyboardKey.numpadSubtract,
        LogicalKeyboardKey.numpadMultiply, LogicalKeyboardKey.numpadDivide,
        LogicalKeyboardKey.numpadDecimal, LogicalKeyboardKey.numpadComma,
        LogicalKeyboardKey.convert, LogicalKeyboardKey.nonConvert,
        LogicalKeyboardKey.audioVolumeUp, LogicalKeyboardKey.audioVolumeDown,
        LogicalKeyboardKey.audioVolumeMute, LogicalKeyboardKey.mediaPlayPause,
        LogicalKeyboardKey.mediaStop, LogicalKeyboardKey.mediaTrackNext,
        LogicalKeyboardKey.mediaTrackPrevious, LogicalKeyboardKey.browserHome,
        LogicalKeyboardKey.launchMail, LogicalKeyboardKey.sleep,
        // Listed out rather than read back from the table, so the test states
        // the requirement independently of how the table happens to build it.
        LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4, LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7, LogicalKeyboardKey.f8, LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
        LogicalKeyboardKey.f13, LogicalKeyboardKey.f14, LogicalKeyboardKey.f15,
        LogicalKeyboardKey.f16, LogicalKeyboardKey.f17, LogicalKeyboardKey.f18,
        LogicalKeyboardKey.f19, LogicalKeyboardKey.f20, LogicalKeyboardKey.f21,
        LogicalKeyboardKey.f22, LogicalKeyboardKey.f23, LogicalKeyboardKey.f24,
        LogicalKeyboardKey.numpad0, LogicalKeyboardKey.numpad1,
        LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
        LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5,
        LogicalKeyboardKey.numpad6, LogicalKeyboardKey.numpad7,
        LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
      ];
      for (var c = 'a'.codeUnitAt(0); c <= 'z'.codeUnitAt(0); c++) {
        everyPhysicalKey.add(LogicalKeyboardKey(c));
      }
      for (var c = '0'.codeUnitAt(0); c <= '9'.codeUnitAt(0); c++) {
        everyPhysicalKey.add(LogicalKeyboardKey(c));
      }

      final unmapped = everyPhysicalKey
          .where((k) => vkFor(k) == null)
          .map((k) => k.debugName ?? k.keyLabel)
          .toList();

      expect(unmapped, isEmpty, reason: 'not bindable in the background');
    });

    test('distinct keys never share a VK code, except where Windows does', () {
      // A duplicate would make two keybinds indistinguishable to the hook, so
      // one of them would fire on the other's key. Numpad Enter really does
      // share VK_RETURN with the main Enter — telling them apart needs the
      // extended-key flag the hook does not send.
      final byVk = <int, Set<String>>{};
      for (final key in LogicalKeyboardKey.knownLogicalKeys) {
        final vk = vkFor(key);
        if (vk == null) continue;
        byVk.putIfAbsent(vk, () => {}).add(key.debugName ?? '?');
      }

      expect(byVk.values.where((names) => names.length > 1), [
        {'Enter', 'Numpad Enter'},
      ]);
    });

    test('a key Windows has no VK for returns null, not a wrong code', () {
      // Better a keybind that only works in the foreground than one that
      // fires on somebody else's key. Fn is resolved inside the keyboard and
      // never reaches the OS; `shift` is the combined modifier, which
      // describes a state rather than a keypress.
      expect(vkFor(LogicalKeyboardKey.fn), isNull);
      expect(vkFor(LogicalKeyboardKey.shift), isNull);
      expect(vkFor(LogicalKeyboardKey.tvPower), isNull);
    });
  });
}
