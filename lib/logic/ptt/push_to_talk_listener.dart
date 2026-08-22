import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import 'win32_key_codes.dart';

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
    debugPrint(
      'PushToTalkListener: keyId 0x${keyId.toRadixString(16)} has no Win32 VK '
      'mapping, so PTT cannot fire while the app is in the background.',
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
