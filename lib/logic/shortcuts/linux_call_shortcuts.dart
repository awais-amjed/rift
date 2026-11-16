import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/classes/call_shortcuts.dart';
import '../cubits/app/app_cubit.dart';
import '../cubits/livekit/livekit_cubit.dart';
import '../helper_methods.dart';
import '../ptt/global_shortcuts_portal.dart';
import '../ptt/release_debounce.dart';
import '../ptt/xdg_trigger.dart';
import '../services/linux_desktop_entry.dart';
import 'call_shortcut_actions.dart';
import 'call_shortcut_listener.dart';

/// The call shortcuts from anywhere on Linux, through the desktop's
/// GlobalShortcuts portal, kept in step with the keys picked in Settings.
///
/// A session of their own, beside push-to-talk's, so changing one never
/// brings the desktop's dialog back for the other. Only actions with a key
/// are bound; with none left the session closes, since an open one grabs its
/// keys from every other app.
///
/// The desktop keeps the keys it granted (as for push-to-talk,
/// `LinuxPushToTalk`), so what it reports is stored back as the keys picked,
/// and Settings sends a change to the desktop's own page.
class LinuxCallShortcuts {
  final AppCubit _app;
  final LiveKitCubit _liveKit;
  final GlobalShortcutsPortal _portal = GlobalShortcutsPortal(
    sessionTag: 'rift_calls',
  );
  late final Map<CallShortcut, ReleaseDebounce> _presses = {
    for (final action in CallShortcut.values)
      action: ReleaseDebounce(
        // Fires on the key going down; a held key's repeats are one press.
        onChanged: (pressed) {
          if (pressed && !CallShortcutListener.capturing) {
            runCallShortcut(action, _liveKit);
          }
        },
      ),
  };
  StreamSubscription<AppState>? _settings;

  /// Bumped on every change, so a bind that finishes after the keys moved on
  /// (the user took a while in the desktop's dialog) is thrown away.
  int _generation = 0;
  List<PortalShortcut>? _applied;

  LinuxCallShortcuts(this._app, this._liveKit);

  void start() {
    _settings = _app.stream.listen(_apply);
    _apply(_app.state);
  }

  Future<void> dispose() async {
    _generation++;
    await _settings?.cancel();
    for (final debounce in _presses.values) {
      debounce.dispose();
    }
    await _portal.dispose();
  }

  Future<void> _apply(AppState state) async {
    final wanted = portalShortcutsFor(state.callShortcuts);
    if (listEquals(wanted, _applied)) return;
    _applied = wanted;
    final generation = ++_generation;

    _app.setDesktopCallShortcuts(const {});
    for (final debounce in _presses.values) {
      debounce.reset();
    }
    if (wanted.isEmpty) {
      await _portal.close();
      return;
    }

    await LinuxDesktopEntry.ensure();
    final triggers = await _portal.bindAll(
      appId: LinuxDesktopEntry.appId,
      shortcuts: wanted,
      onPress: (id, timestamp) => _debounceFor(id)?.press(timestamp),
      onRelease: (id, timestamp) => _debounceFor(id)?.release(timestamp),
      onTriggersChanged: (triggers) {
        if (generation == _generation) _adopt(triggers);
      },
    );
    if (generation != _generation) return;
    HelperMethods.printDebug(
      triggers == null
          ? 'LinuxCallShortcuts: no desktop shortcuts, in-window only'
          : 'LinuxCallShortcuts: desktop shortcuts bound $triggers',
    );
    if (triggers != null) _adopt(triggers);
  }

  ReleaseDebounce? _debounceFor(String id) {
    final action = callShortcutForPortalId(id);
    return action == null ? null : _presses[action];
  }

  /// Takes what the desktop says into Rift: which actions it delivers, and
  /// their keys as the stored ones. [_applied] moves first, so storing them
  /// does not look like a change and bind all over again.
  void _adopt(Map<String, String> triggers) {
    _app.setDesktopCallShortcuts(deliveredActions(triggers));
    final current = _app.state.callShortcuts;
    final adopted = adoptDesktopKeys(current, triggers);
    if (adopted == current) return;
    _applied = portalShortcutsFor(adopted);
    _app.setCallShortcuts(adopted);
  }
}

// ── Pure helpers ─────────────────────────────────────────────────────────

/// The id the desktop knows [action] by.
String portalIdFor(CallShortcut action) => 'call-${action.name}';

CallShortcut? callShortcutForPortalId(String id) {
  for (final action in CallShortcut.values) {
    if (portalIdFor(action) == id) return action;
  }
  return null;
}

/// What to ask the desktop for: each action with keys, suggesting them.
List<PortalShortcut> portalShortcutsFor(CallShortcuts shortcuts) => [
  for (final action in CallShortcut.values)
    if (shortcuts[action] case final keys?)
      PortalShortcut(
        id: portalIdFor(action),
        description: callShortcutTitle(action),
        preferredTrigger: xdgTriggerForShortcut(keys),
      ),
];

/// The actions the desktop reported a key for.
Set<CallShortcut> deliveredActions(Map<String, String> triggers) => {
  for (final MapEntry(key: id, value: trigger) in triggers.entries)
    if (trigger.isNotEmpty) ?callShortcutForPortalId(id),
};

/// [stored] with each key the desktop reported in its place. A key Rift
/// cannot read, or none, leaves the stored one.
CallShortcuts adoptDesktopKeys(
  CallShortcuts stored,
  Map<String, String> triggers,
) {
  var adopted = stored;
  for (final MapEntry(key: id, value: trigger) in triggers.entries) {
    final action = callShortcutForPortalId(id);
    final keys = shortcutForTriggerDescription(trigger);
    if (action == null || keys == null || adopted[action] == keys) continue;
    adopted = adopted.withKeys(action, keys);
  }
  return adopted;
}
