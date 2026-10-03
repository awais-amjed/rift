import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';
import 'linux_push_to_talk.dart';
import 'mouse_button_bind.dart';
import 'win32_key_codes.dart';

/// Global keyboard listener that maps the configured keybind to PTT pressed state.
///
/// On Windows a WH_KEYBOARD_LL hook installed in the native runner sends every
/// key event through [_kPttChannel] so PTT continues to work while the app is
/// running in the background.  Flutter's [HardwareKeyboard] still handles the
/// in-focus case, but its events are ignored if the background hook is active
/// to avoid ordering artefacts.
///
/// On Linux the background half is the desktop's GlobalShortcuts portal
/// ([LinuxPushToTalk]). Where it is missing or declined, the in-focus handler
/// is all there is.
///
/// A mouse button keybind ([MouseButtonBind]) is heard the same two ways: the
/// Windows hook reports buttons alongside keys, and in the window every
/// pointer event passes [_handlePointer]. The portal only takes keys, so on
/// Linux a button works while Rift has the pointer and nowhere else.
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
  LinuxPushToTalk? _linux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);

    if (!kIsWeb && Platform.isWindows) {
      _bgSub = _kPttChannel.receiveBroadcastStream().listen(_handleBgKeyEvent);
    }
    if (!kIsWeb && Platform.isLinux) {
      _linux = LinuxPushToTalk(
        context.read<AppCubit>(),
        context.read<LiveKitCubit>(),
      )..start();
    }
  }

  @override
  void dispose() {
    _bgSub?.cancel();
    _linux?.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The portal reports the key whichever window has focus, release included,
    // so losing focus is no sign the key went up — and forcing one here would
    // leave the debounce believing the key is still held.
    if (_linux?.isBound ?? false) return;
    if (state != AppLifecycleState.resumed) {
      context.read<LiveKitCubit>().setPushToTalkPressed(false);
    }
  }

  // ── In-focus handler (Flutter HardwareKeyboard) ──────────────────────────

  bool _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return false;
    if (_linux?.isBound ?? false) return false;

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

  // ── In-window mouse button ───────────────────────────────────────────────

  /// Whether the bound button was down at the last pointer event, so only a
  /// change reaches the cubit — every pointer move passes through here.
  bool _buttonHeld = false;

  void _handlePointer(PointerEvent event) {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
    if (event.kind != PointerDeviceKind.mouse) return;

    final appState = context.read<AppCubit>().state;
    final keyId = appState.pushToTalkKeyId;
    final button = keyId == null ? null : MouseButtonBind.buttonOf(keyId);
    if (!appState.pushToTalkEnabled || button == null) {
      _buttonHeld = false;
      return;
    }

    final held =
        event is! PointerUpEvent &&
        event is! PointerCancelEvent &&
        event.buttons & button != 0;
    if (held == _buttonHeld) return;
    _buttonHeld = held;
    context.read<LiveKitCubit>().setPushToTalkPressed(held);
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

    final expectedVk = win32VkForLogicalKey(appState.pushToTalkKeyId!);
    if (expectedVk == null) {
      _warnUnmappedKeybind(appState.pushToTalkKeyId!);
      return;
    }
    if (vkCode != expectedVk) return;

    context.read<LiveKitCubit>().setPushToTalkPressed(isDown);
  }

  /// Keybinds already complained about, so an unmappable one is reported once
  /// rather than on every keystroke.
  static final Set<int> _warnedKeyIds = <int>{};

  static void _warnUnmappedKeybind(int keyId) {
    if (!_warnedKeyIds.add(keyId)) return;
    HelperMethods.printDebug(
      'PushToTalkListener: keyId 0x${keyId.toRadixString(16)} has no Win32 VK '
      'mapping, so PTT cannot fire while the app is in the background.',
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
