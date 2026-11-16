import 'dart:async';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../ptt/windows_key_hook.dart';
import 'call_shortcut_actions.dart';
import 'call_shortcut_listener.dart';
import 'hook_key_state.dart';

/// The call shortcuts on Windows, from the runner's hook, whichever window
/// has focus.
///
/// The hook hears a press with Rift in front too, so while this runs the
/// window's own key handler leaves the call shortcuts alone: a press heard
/// twice would mute and unmute at once. Like push-to-talk's, the hook passes
/// every key on, so the app in front still gets it.
class WindowsCallShortcuts {
  final AppCubit _app;
  final LiveKitCubit _liveKit;
  final HookKeyState _keys = HookKeyState();
  StreamSubscription<HookKey>? _sub;

  WindowsCallShortcuts(this._app, this._liveKit);

  void start() {
    _sub = WindowsKeyHook.keys.listen((key) {
      final action = _keys.onKey(key, _app.state.callShortcuts);
      // The press that picks a shortcut in Settings is not one to act on;
      // the key state above still saw it, so its release lines up.
      if (action == null || CallShortcutListener.capturing) return;
      runCallShortcut(action, _liveKit);
    });
  }

  Future<void> dispose() async => _sub?.cancel();
}
