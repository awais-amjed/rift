import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';
import 'linux_global_shortcuts.dart';
import 'mouse_button_bind.dart';
import 'win32_key_codes.dart';
import 'windows_key_hook.dart';

/// Global keyboard listener that maps the configured keybind to PTT pressed state.
///
/// On Windows a WH_KEYBOARD_LL hook installed in the native runner sends every
/// key event through [WindowsKeyHook] so PTT continues to work while the app is
/// running in the background. It is in only while a key is bound, and the
/// mouse's hook only while push-to-talk is on a button ([hooksWantedFor]).  Flutter's [HardwareKeyboard] reports the key
/// too while Rift has focus; the two agree, and the cubit takes a press it
/// already holds as nothing.
///
/// On Linux the background half is the desktop's GlobalShortcuts portal
/// ([LinuxGlobalShortcuts]). Where it is missing or declined, the in-focus handler
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
  StreamSubscription<HookKey>? _bgSub;
  StreamSubscription<({bool keyboard, bool mouse})>? _hookWants;
  LinuxGlobalShortcuts? _linux;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
    _buttonKeyId = context.read<AppCubit>().state.pushToTalkKeyId;

    if (!kIsWeb && Platform.isWindows) {
      _bgSub = WindowsKeyHook.keys.listen(_handleBgKeyEvent);
      final app = context.read<AppCubit>();
      ({bool keyboard, bool mouse}) wanted(AppState state) => hooksWantedFor(
        pushToTalk: state.pushToTalkEnabled,
        pushToTalkKeyId: state.pushToTalkKeyId,
        calls: state.callShortcuts,
      );
      unawaited(_want(wanted(app.state)));
      _hookWants = app.stream
          .map(wanted)
          .distinct()
          .listen((hooks) => unawaited(_want(hooks)));
    }
    if (!kIsWeb && Platform.isLinux) {
      _linux = LinuxGlobalShortcuts(
        context.read<AppCubit>(),
        context.read<LiveKitCubit>(),
      )..start();
    }
  }

  @override
  void dispose() {
    _bgSub?.cancel();
    _hookWants?.cancel();
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
    if (_linux?.isPushToTalkBound ?? false) return;
    // So does the Windows hook. There a mouse button pressed over another
    // window takes the focus from Rift, and this let go of the key the moment
    // it went down: both tones at once, and the mic shut while still held.
    // Not a key the hook cannot name (an ü, AZERTY's top row): that one is
    // heard only in the window, so its release outside it is never heard.
    if (_bgSub != null && _hookHearsPushToTalk) return;
    if (state != AppLifecycleState.resumed) {
      context.read<LiveKitCubit>().setPushToTalkPressed(
        false,
        via: 'window ${state.name}',
      );
    }
  }

  bool get _hookHearsPushToTalk {
    final keyId = context.read<AppCubit>().state.pushToTalkKeyId;
    return keyId != null && win32VkForLogicalKey(keyId) != null;
  }

  // ── In-focus handler (Flutter HardwareKeyboard) ──────────────────────────

  bool _handleKeyEvent(KeyEvent event) {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return false;
    if (_linux?.isPushToTalkBound ?? false) return false;

    final appState = context.read<AppCubit>().state;
    final keyId = appState.pushToTalkKeyId;
    if (!appState.pushToTalkEnabled || keyId == null) return false;

    if (event.logicalKey.keyId != keyId) return false;

    if (event is KeyUpEvent) {
      _keyDownSeen = false;
      context.read<LiveKitCubit>().setPushToTalkPressed(false, via: 'window');
      return false;
    }

    if (event is KeyDownEvent) _keyDownSeen = true;
    // A repeat counts only for a press heard here. The key just picked in
    // Settings went down before it was the key, so its repeats would have
    // put the person on the mic for as long as they held it.
    if (event is KeyDownEvent || (event is KeyRepeatEvent && _keyDownSeen)) {
      context.read<LiveKitCubit>().setPushToTalkPressed(true, via: 'window');
    }
    return false;
  }

  /// Whether the push-to-talk key's press was heard by [_handleKeyEvent].
  bool _keyDownSeen = false;

  // ── In-window mouse button ───────────────────────────────────────────────

  /// Whether the bound button was down at the last pointer event, so only a
  /// change reaches the cubit — every pointer move passes through here.
  bool _buttonHeld = false;

  /// The keybind [_buttonHeld] is about.
  int? _buttonKeyId;

  void _handlePointer(PointerEvent event) {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
    if (event.kind != PointerDeviceKind.mouse) return;
    // Only these say which buttons are down. A scroll, a hover or the pointer
    // arriving carries none, and read as a release a turn of the wheel while
    // talking shut the mic with the button still held.
    if (event is! PointerDownEvent &&
        event is! PointerMoveEvent &&
        event is! PointerUpEvent &&
        event is! PointerCancelEvent) {
      return;
    }

    final appState = context.read<AppCubit>().state;
    final keyId = appState.pushToTalkKeyId;
    final button = keyId == null ? null : MouseButtonBind.buttonOf(keyId);
    if (!appState.pushToTalkEnabled || button == null) {
      _buttonHeld = false;
      _buttonKeyId = keyId;
      return;
    }

    final held =
        event is! PointerUpEvent &&
        event is! PointerCancelEvent &&
        event.buttons & button != 0;
    // A button just picked in Settings is already down: taken as it is, so
    // the first move after does not open the mic until it is let go.
    if (keyId != _buttonKeyId) {
      _buttonKeyId = keyId;
      _buttonHeld = held;
      return;
    }
    if (held == _buttonHeld) return;
    _buttonHeld = held;
    context.read<LiveKitCubit>().setPushToTalkPressed(held, via: 'window');
  }

  // ── Background hook handler (native EventChannel) ────────────────────────

  void _handleBgKeyEvent(HookKey key) {
    final appState = context.read<AppCubit>().state;
    if (!appState.pushToTalkEnabled || appState.pushToTalkKeyId == null) {
      return;
    }

    final expectedVk = win32VkForLogicalKey(appState.pushToTalkKeyId!);
    if (expectedVk == null) {
      _warnUnmappedKeybind(appState.pushToTalkKeyId!);
      return;
    }
    if (key.vk != expectedVk) return;

    context.read<LiveKitCubit>().setPushToTalkPressed(
      key.down,
      via: key.byCheck ? 'hook held-key check' : 'hook',
    );
  }

  static Future<void> _want(({bool keyboard, bool mouse}) hooks) async {
    try {
      await WindowsKeyHook.want(keyboard: hooks.keyboard, mouse: hooks.mouse);
    } catch (e) {
      HelperMethods.printDebug('PushToTalkListener: hooks not set – $e');
    }
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
