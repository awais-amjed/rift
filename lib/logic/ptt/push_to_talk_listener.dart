import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';

/// Global keyboard listener that maps the configured keybind to PTT pressed state.
///
/// On Windows a WH_KEYBOARD_LL hook installed in the native runner sends every
/// key event through [_kPttChannel] so PTT continues to work while the app is
/// running in the background.  Flutter's [HardwareKeyboard] still handles the
/// in-focus case, but its events are ignored if the background hook is active
/// to avoid ordering artefacts.
class PushToTalkListener extends StatefulWidget {
  final Widget child;

  const PushToTalkListener({super.key, required this.child});

  @override
  State<PushToTalkListener> createState() => _PushToTalkListenerState();
}

class _PushToTalkListenerState extends State<PushToTalkListener>
    with WidgetsBindingObserver {
  static const EventChannel _kPttChannel = EventChannel('rift/ptt_keys');

  StreamSubscription<dynamic>? _bgSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);

    if (!kIsWeb && Platform.isWindows) {
      _bgSub = _kPttChannel.receiveBroadcastStream().listen(_handleBgKeyEvent);
    }
  }

  @override
  void dispose() {
    _bgSub?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      context.read<LiveKitCubit>().setPushToTalkPressed(false);
    }
  }

  // ── In-focus handler (Flutter HardwareKeyboard) ──────────────────────────

  bool _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || !Platform.isWindows) return false;

    final appState = context.read<AppCubit>().state;
    final keyId = appState.pushToTalkKeyId;
    if (!appState.pushToTalkEnabled || keyId == null) return false;

    if (event.logicalKey.keyId != keyId) return false;

    if (event is KeyUpEvent) {
      context.read<LiveKitCubit>().setPushToTalkPressed(false);
      return false;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      context.read<LiveKitCubit>().setPushToTalkPressed(true);
    }
    return false;
  }

  // ── Background hook handler (native EventChannel) ────────────────────────

  void _handleBgKeyEvent(dynamic event) {
    if (event is! Map) return;

    final appState = context.read<AppCubit>().state;
    if (!appState.pushToTalkEnabled || appState.pushToTalkKeyId == null) {
      return;
    }

    final vkCode = event['vk_code'] as int?;
    final isDown = event['is_down'] as bool?;
    if (vkCode == null || isDown == null) return;

    final expectedVk = _logicalKeyIdToWin32Vk(appState.pushToTalkKeyId!);
    if (expectedVk == null || vkCode != expectedVk) return;

    context.read<LiveKitCubit>().setPushToTalkPressed(isDown);
  }

  /// Converts a Flutter [LogicalKeyboardKey.keyId] to a Win32 Virtual Key
  /// code so it can be compared with the vk_code delivered by the native hook.
  ///
  /// Covers the most common PTT keys: letters, digits, space, control
  /// characters that share their ASCII value with Win32 VKs (Tab, Enter,
  /// Escape, Backspace), F1–F24, and Numpad 0–9.
  static int? _logicalKeyIdToWin32Vk(int keyId) {
    // Lowercase letters a–z (Flutter 0x61–0x7A) → Win32 VK_A–VK_Z (0x41–0x5A)
    if (keyId >= 0x61 && keyId <= 0x7A) return keyId - 0x20;

    // Digits 0–9 (Flutter == ASCII == Win32)
    if (keyId >= 0x30 && keyId <= 0x39) return keyId;

    // Space, and ASCII control chars whose Win32 VK matches the code point
    switch (keyId) {
      case 0x08:
        return 0x08; // Backspace / VK_BACK
      case 0x09:
        return 0x09; // Tab / VK_TAB
      case 0x0D:
        return 0x0D; // Enter / VK_RETURN
      case 0x1B:
        return 0x1B; // Escape / VK_ESCAPE
      case 0x20:
        return 0x20; // Space / VK_SPACE
    }

    // F1–F24 (Flutter 0x100000063–0x10000007A → Win32 VK_F1–VK_F24 0x70–0x87)
    if (keyId >= 0x100000063 && keyId <= 0x10000007A) {
      return 0x70 + (keyId - 0x100000063);
    }

    // Numpad 0–9 (Flutter 0x200000030–0x200000039 → Win32 VK_NUMPAD0–9 0x60–0x69)
    if (keyId >= 0x200000030 && keyId <= 0x200000039) {
      return 0x60 + (keyId - 0x200000030);
    }

    // Arrow / navigation keys
    const Map<int, int> extraKeys = {
      0x100000301: 0x28, // arrowDown  → VK_DOWN
      0x100000302: 0x25, // arrowLeft  → VK_LEFT
      0x100000303: 0x27, // arrowRight → VK_RIGHT
      0x100000304: 0x26, // arrowUp    → VK_UP
      0x100000305: 0x21, // pageUp     → VK_PRIOR
      0x100000306: 0x22, // pageDown   → VK_NEXT
      0x100000307: 0x23, // end        → VK_END
      0x100000308: 0x24, // home       → VK_HOME
      0x100000401: 0x2D, // insert     → VK_INSERT
      0x100000407: 0x2E, // delete     → VK_DELETE
    };

    return extraKeys[keyId];
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
