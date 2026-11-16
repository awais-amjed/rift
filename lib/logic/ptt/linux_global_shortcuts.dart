import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/classes/call_shortcuts.dart';
import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';
import '../services/linux_desktop_entry.dart';
import '../shortcuts/call_shortcut_actions.dart';
import '../shortcuts/call_shortcut_listener.dart';
import '../shortcuts/linux_call_shortcuts.dart';
import 'global_shortcuts_portal.dart';
import 'mouse_button_bind.dart';
import 'release_debounce.dart';
import 'xdg_trigger.dart';

/// Keeps the desktop's shortcuts in step with the settings: push-to-talk and
/// the call shortcuts, in one list.
///
/// One list because GNOME keeps one saved list per app and each bind replaces
/// it. Push-to-talk and the call shortcuts in sessions of their own dropped
/// each other's keys, and the desktop's dialog came back on every launch
/// (checked Nov 16 with the portal). Asked for together, a shortcut the
/// desktop already granted is answered at once, and the dialog comes only
/// when there is a new one.
///
/// Bound while there is anything to ask for, closed the moment there is not —
/// the desktop grabs the keys from every other app while a session is open,
/// so leaving one behind would break those keys everywhere. Any change binds
/// the whole list again, suggesting the keys picked; the desktop keeps the
/// keys it already granted, and Rift stores those back as its own.
///
/// A mouse button is never offered for push-to-talk: the portal only takes
/// keys, and binding with no suggestion would have the desktop ask for one.
/// The in-window handler hears a button instead.
class LinuxGlobalShortcuts {
  final AppCubit _app;
  final LiveKitCubit _liveKit;
  final GlobalShortcutsPortal _portal = GlobalShortcutsPortal();
  late final ReleaseDebounce _pushToTalk = ReleaseDebounce(
    onChanged: (pressed) =>
        _liveKit.setPushToTalkPressed(pressed, via: 'portal'),
  );
  late final Map<CallShortcut, ReleaseDebounce> _calls = {
    for (final action in CallShortcut.values)
      action: ReleaseDebounce(
        // On the key going down; a held key's repeats are one press.
        onChanged: (pressed) {
          if (pressed && !CallShortcutListener.capturing) {
            runCallShortcut(action, _liveKit);
          }
        },
      ),
  };
  StreamSubscription<AppState>? _settings;

  /// Bumped on every change, so a bind that finishes after the settings moved
  /// on (the user took a while in the desktop's dialog) is thrown away.
  int _generation = 0;
  List<PortalShortcut>? _applied;
  bool _pushToTalkBound = false;

  LinuxGlobalShortcuts(this._app, this._liveKit);

  /// Whether the desktop is delivering a known push-to-talk key. While it is,
  /// the key never reaches the focused window either, and the in-window
  /// handler stands down so a press is never counted twice.
  ///
  /// A session with no key assigned does not count. The session stays open,
  /// so a key the user binds later in the desktop's own config still works,
  /// but until then the in-window key is the only one there is — standing it
  /// down too left push-to-talk dead everywhere.
  bool get isPushToTalkBound => _pushToTalkBound;

  void start() {
    // The latest state, not the one each change carries: storing what the
    // desktop reports is several changes in a row, and the ones in between
    // would look like new keys to bind.
    _settings = _app.stream.listen((_) => _apply());
    _apply();
  }

  Future<void> dispose() async {
    _generation++;
    await _settings?.cancel();
    _pushToTalk.dispose();
    for (final debounce in _calls.values) {
      debounce.dispose();
    }
    await _portal.dispose();
  }

  Future<void> _apply() async {
    final wanted = _wantedFor(_app.state);
    if (listEquals(wanted, _applied)) return;
    _applied = wanted;
    final generation = ++_generation;

    _setPushToTalkKey(null);
    _app.setDesktopCallShortcuts(const {});
    _pushToTalk.reset();
    for (final debounce in _calls.values) {
      debounce.reset();
    }
    final asksPushToTalk = wanted.any(
      (s) => s.id == GlobalShortcutsPortal.pushToTalkId,
    );
    if (wanted.isEmpty) {
      _app.setDesktopPushToTalkPending(false);
      await _portal.close();
      return;
    }

    _app.setDesktopPushToTalkPending(asksPushToTalk);
    await LinuxDesktopEntry.ensure();
    final triggers = await _portal.bind(
      appId: LinuxDesktopEntry.appId,
      shortcuts: wanted,
      onPress: (id, timestamp) => _debounceFor(id)?.press(timestamp),
      onRelease: (id, timestamp) => _debounceFor(id)?.release(timestamp),
      onTriggersChanged: (triggers) {
        if (generation == _generation) _adopt(triggers);
      },
    );
    if (generation != _generation) return;
    _adopt(triggers ?? const {});
    _app.setDesktopPushToTalkPending(false);
    HelperMethods.printDebug(
      triggers == null
          ? 'LinuxGlobalShortcuts: no desktop shortcuts, in-window only'
          : 'LinuxGlobalShortcuts: desktop shortcuts bound $triggers',
    );
  }

  ReleaseDebounce? _debounceFor(String id) {
    if (id == GlobalShortcutsPortal.pushToTalkId) return _pushToTalk;
    final action = callShortcutForPortalId(id);
    return action == null ? null : _calls[action];
  }

  /// Takes what the desktop says into Rift: which keys it delivers, and those
  /// keys as the stored ones. [_applied] moves first, so storing them does
  /// not look like a change and bind all over again.
  void _adopt(Map<String, String> triggers) {
    final state = _app.state;
    final pushToTalk = triggers[GlobalShortcutsPortal.pushToTalkId];
    final pushToTalkKey = pushToTalk == null
        ? null
        : keybindForTriggerDescription(pushToTalk);
    final calls = adoptDesktopKeys(state.callShortcuts, triggers);
    _applied = desktopShortcutsFor(
      pushToTalk: state.pushToTalkEnabled,
      pushToTalkKeyId: pushToTalkKey?.keyId ?? state.pushToTalkKeyId,
      calls: calls,
    );

    _setPushToTalkKey(pushToTalk);
    if (pushToTalkKey != null && pushToTalkKey.keyId != state.pushToTalkKeyId) {
      _app.setPushToTalkKeybind(
        keyId: pushToTalkKey.keyId,
        label: pushToTalkKey.label,
      );
    }
    _app.setDesktopCallShortcuts(deliveredActions(triggers));
    _app.setCallShortcuts(calls);
  }

  /// What the desktop says the push-to-talk key is, shown in Settings.
  void _setPushToTalkKey(String? trigger) {
    final known = (trigger?.isNotEmpty ?? false) ? trigger : null;
    _pushToTalkBound = known != null;
    if (_app.state.desktopPushToTalkKey != known) {
      _app.setDesktopPushToTalkKey(known);
    }
  }

  static List<PortalShortcut> _wantedFor(AppState state) => desktopShortcutsFor(
    pushToTalk: state.pushToTalkEnabled,
    pushToTalkKeyId: state.pushToTalkKeyId,
    calls: state.callShortcuts,
  );
}

/// Every shortcut to ask the desktop for: push-to-talk while it is on with a
/// key, then each call shortcut with keys.
List<PortalShortcut> desktopShortcutsFor({
  required bool pushToTalk,
  required int? pushToTalkKeyId,
  required CallShortcuts calls,
}) => [
  if (pushToTalk &&
      pushToTalkKeyId != null &&
      !MouseButtonBind.isMouse(pushToTalkKeyId))
    PortalShortcut(
      id: GlobalShortcutsPortal.pushToTalkId,
      description: 'Push to talk',
      preferredTrigger: xdgTriggerForKeyId(pushToTalkKeyId),
    ),
  ...portalShortcutsFor(calls),
];
