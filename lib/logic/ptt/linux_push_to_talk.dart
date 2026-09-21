import 'dart:async';

import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';
import 'global_shortcuts_portal.dart';
import 'linux_desktop_entry.dart';
import 'release_debounce.dart';
import 'xdg_trigger.dart';

/// Keeps the desktop's push-to-talk shortcut in step with the setting.
///
/// Bound while push-to-talk is on and a key is set, closed the moment either
/// stops being true — the desktop grabs the key from every other app while a
/// session is open, so leaving one behind would break that key everywhere.
/// A new keybind closes the old session and binds again, suggesting the new
/// key; the desktop may ask the user to confirm it.
class LinuxPushToTalk {
  final AppCubit _app;
  final LiveKitCubit _liveKit;
  final GlobalShortcutsPortal _portal = GlobalShortcutsPortal();
  late final ReleaseDebounce _debounce = ReleaseDebounce(
    onChanged: _liveKit.setPushToTalkPressed,
  );
  StreamSubscription<AppState>? _settings;

  /// Bumped on every change, so a bind that finishes after the setting moved
  /// on (the user took a while in the desktop's dialog) is thrown away.
  int _generation = 0;
  ({bool enabled, int? keyId})? _applied;
  bool _bound = false;

  LinuxPushToTalk(this._app, this._liveKit);

  /// Whether the desktop is delivering a known key. While it is, the key
  /// never reaches the focused window either, and the in-window handler
  /// stands down so a press is never counted twice.
  ///
  /// A session with no key assigned does not count. The session stays open,
  /// so a key the user binds later in the desktop's own config still works,
  /// but until then the in-window key is the only one there is — standing it
  /// down too left push-to-talk dead everywhere.
  bool get isBound => _bound;

  void start() {
    _settings = _app.stream.listen(_apply);
    _apply(_app.state);
  }

  Future<void> dispose() async {
    _generation++;
    await _settings?.cancel();
    _debounce.dispose();
    await _portal.dispose();
  }

  void _setBound(String? trigger) {
    final known = (trigger?.isNotEmpty ?? false) ? trigger : null;
    _bound = known != null;
    if (_app.state.desktopPushToTalkKey != known) {
      _app.setDesktopPushToTalkKey(known);
    }
  }

  Future<void> _apply(AppState state) async {
    final wanted = (
      enabled: state.pushToTalkEnabled,
      keyId: state.pushToTalkKeyId,
    );
    if (wanted == _applied) return;
    _applied = wanted;
    final generation = ++_generation;

    _setBound(null);
    _debounce.reset();
    final keyId = wanted.keyId;
    if (!wanted.enabled || keyId == null) {
      await _portal.close();
      return;
    }

    await LinuxDesktopEntry.ensure();
    final trigger = await _portal.bind(
      appId: LinuxDesktopEntry.appId,
      preferredTrigger: xdgTriggerForKeyId(keyId),
      onPress: _debounce.press,
      onRelease: _debounce.release,
      onTriggerChanged: (trigger) {
        if (generation == _generation) _setBound(trigger);
      },
    );
    if (generation != _generation) return;
    _setBound(trigger);
    HelperMethods.printDebug(
      _bound
          ? 'LinuxPushToTalk: desktop shortcut bound ($trigger)'
          : trigger != null
          ? 'LinuxPushToTalk: desktop session open, no key assigned yet'
          : 'LinuxPushToTalk: no desktop shortcut, in-window only',
    );
  }
}
