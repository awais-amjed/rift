import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/classes/call_shortcuts.dart';
import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../services/host_platform.dart';

/// Hears the mute and deafen shortcuts picked in Settings and presses the
/// matching button.
///
/// A [HardwareKeyboard] handler, not a Shortcuts binding: those follow focus,
/// and `KeyboardDismisser` drops focus on every click, so a bound shortcut
/// would stop working the first time the person clicked anything. Flutter
/// only gets keys while the window is in front, which is the point: these
/// are in-app shortcuts, unlike push-to-talk.
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
  @override
  void initState() {
    super.initState();
    if (HostPlatform.isDesktop) HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    // Down only: holding the keys must not flip mute on every repeat.
    if (event is! KeyDownEvent || CallShortcutListener.capturing) return false;
    final shortcuts = context.read<AppCubit>().state.callShortcuts;
    final action = shortcuts.actionFor(
      event.logicalKey,
      HardwareKeyboard.instance,
    );
    if (action == null) return false;
    final livekit = context.read<LiveKitCubit>();
    switch (action) {
      case CallShortcut.mute:
        livekit.toggleMicrophone();
      case CallShortcut.deafen:
        livekit.toggleDeafen();
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
