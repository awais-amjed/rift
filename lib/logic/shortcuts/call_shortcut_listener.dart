import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../services/host_platform.dart';
import 'call_shortcut_actions.dart';
import 'windows_call_shortcuts.dart';

/// Hears the call shortcuts picked in Settings and presses the
/// matching button, from anywhere.
///
/// In the window, a [HardwareKeyboard] handler, not a Shortcuts binding: those
/// follow focus, and `KeyboardDismisser` drops focus on every click, so a
/// bound shortcut would stop working the first time the person clicked
/// anything. Flutter only gets keys while the window is in front, so the
/// background comes from elsewhere: on Windows the runner's hook
/// ([WindowsCallShortcuts]), which hears the window's presses as well, so the
/// handler here stands down there; on Linux the desktop
/// (`LinuxGlobalShortcuts`, started by `PushToTalkListener` with
/// push-to-talk's key, as the desktop wants them in one list), which takes a
/// key it delivers from the window too, so the handler here leaves those
/// actions to it and keeps the rest.
class CallShortcutListener extends StatefulWidget {
  final Widget child;

  const CallShortcutListener({super.key, required this.child});

  /// Set while Settings is listening for a new shortcut, so the press that
  /// picks one does not also mute.
  static bool capturing = false;

  @override
  State<CallShortcutListener> createState() => _CallShortcutListenerState();
}

class _CallShortcutListenerState extends State<CallShortcutListener> {
  WindowsCallShortcuts? _windows;

  @override
  void initState() {
    super.initState();
    if (HostPlatform.isDesktop) HardwareKeyboard.instance.addHandler(_onKey);
    if (!kIsWeb && Platform.isWindows) {
      _windows = WindowsCallShortcuts(
        context.read<AppCubit>(),
        context.read<LiveKitCubit>(),
      )..start();
    }
  }

  @override
  void dispose() {
    _windows?.dispose();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    // The hook has it, Rift in front or not.
    if (_windows != null) return false;
    // Down only: holding the keys must not flip mute on every repeat.
    if (event is! KeyDownEvent || CallShortcutListener.capturing) return false;
    final state = context.read<AppCubit>().state;
    final action = state.callShortcuts.actionFor(
      event.logicalKey,
      HardwareKeyboard.instance,
    );
    if (action == null) return false;
    // The desktop has it; it should never reach here, but if it does, once.
    if (state.desktopCallShortcuts.contains(action)) return false;
    runCallShortcut(action, context.read<LiveKitCubit>());
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
