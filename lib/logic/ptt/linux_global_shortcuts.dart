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

  /// Shortcuts ([refusalKey]) the desktop failed to bind this run, without a
  /// person saying no: not asked for again until their key changes, or every
  /// change would ask again. Push-to-talk refused by a person is kept between
  /// runs instead ([AppState.desktopShortcutsRefused]; a refused call
  /// shortcut loses its keys, [afterDecline]), and what the desktop
  /// granted too ([AppState.desktopShortcutsGranted]): GNOME's dialog is all
  /// or nothing, and saying no to a new call shortcut must not cost
  /// push-to-talk the key it already had.
  final Set<String> _failed = {};

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
    final wanted = notRefused(_wantedFor(_app.state), _refused);

    if (listEquals(wanted, _applied)) return;
    _applied = wanted;
    final generation = ++_generation;

    // The session closes for the bind, so the window hears the key meanwhile.
    final shown = pushToTalkWhileBinding(
      wanted: wanted,
      granted: _app.state.desktopShortcutsGranted,
    );
    _pushToTalkBound = false;
    if (!shown.keepKey) _setPushToTalkKey(null);
    _app.setDesktopCallShortcuts(
      callKeysWhileBinding(
        shown: _app.state.desktopCallShortcuts,
        wanted: wanted,
        granted: _app.state.desktopShortcutsGranted,
      ),
    );
    _pushToTalk.reset();
    for (final debounce in _calls.values) {
      debounce.reset();
    }
    if (wanted.isEmpty) {
      _app.setDesktopPushToTalkPending(false);
      await _portal.close();
      return;
    }

    _app.setDesktopPushToTalkPending(shown.pending);
    await LinuxDesktopEntry.ensure();
    final bound = await _bind(wanted, generation);
    if (generation != _generation) return;
    var triggers = bound.triggers;
    if (triggers == null) {
      final next = afterRefusal(
        asked: wanted,
        granted: _app.state.desktopShortcutsGranted.toSet(),
      );
      _applied = next.retry;
      if (bound.declined) {
        final after = afterDecline(
          calls: _app.state.callShortcuts,
          refused: _app.state.desktopShortcutsRefused,
          declined: next.refused,
        );
        _app.setDesktopShortcutAnswers(refused: after.refused);
        // Leaves the wanted list equal to the retry, so this is no new bind.
        _app.setCallShortcuts(after.calls);
      } else {
        _failed.addAll(next.refused.map(refusalKey));
      }
      if (next.retry.isNotEmpty) {
        triggers = (await _bind(next.retry, generation)).triggers;
        if (generation != _generation) return;
      }
    }
    _adopt(triggers ?? const {});
    if (triggers != null) {
      _app.setDesktopShortcutAnswers(
        granted: triggers.keys.toList(),
        refused: forgetRefused(
          _app.state.desktopShortcutsRefused,
          triggers.keys,
        ),
      );
    }
    _app.setDesktopPushToTalkPending(false);
    HelperMethods.printDebug(
      triggers == null
          ? 'LinuxGlobalShortcuts: no desktop shortcuts, in-window only'
          : 'LinuxGlobalShortcuts: desktop shortcuts bound $triggers',
    );
  }

  Future<({Map<String, String>? triggers, bool declined})> _bind(
    List<PortalShortcut> shortcuts,
    int generation,
  ) => _portal.bind(
    appId: LinuxDesktopEntry.appId,
    shortcuts: shortcuts,
    onPress: (id, timestamp) => _debounceFor(id)?.press(timestamp),
    onRelease: (id, timestamp) => _debounceFor(id)?.release(timestamp),
    onTriggersChanged: (triggers) {
      if (generation == _generation) _adopt(triggers);
    },
  );

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
    _applied = notRefused(
      desktopShortcutsFor(
        pushToTalk: state.pushToTalkEnabled,
        pushToTalkKeyId: pushToTalkKey?.keyId ?? state.pushToTalkKeyId,
        calls: calls,
      ),
      _refused,
    );

    _setPushToTalkKey(pushToTalk);
    if (pushToTalkKey != null && pushToTalkKey.keyId != state.pushToTalkKeyId) {
      _app.setPushToTalkKeybind(
        keyId: pushToTalkKey.keyId,
        label: pushToTalkKey.label,
      );
    }
    _app.setDesktopCallShortcuts(deliveredKeys(triggers));
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

  /// Everything not to ask for: refused by a person, before or now, or failed
  /// this run. A call shortcut a person refuses loses its keys instead
  /// ([afterDecline]); one saved as refused by a build before that is let
  /// through, or setting the same keys again would never ask.
  Set<String> get _refused => {
    ..._app.state.desktopShortcutsRefused.where(
      (key) => callShortcutForPortalId(_idOf(key)) == null,
    ),
    ..._failed,
  };

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

/// What Settings shows for push-to-talk while [wanted] is being bound. One
/// the desktop [granted] before comes back without a dialog, so its key stays
/// shown (`keepKey`) and a dialog meanwhile is for a call shortcut; one not
/// granted yet may be what the dialog asks about (`pending`).
({bool pending, bool keepKey}) pushToTalkWhileBinding({
  required List<PortalShortcut> wanted,
  required Iterable<String> granted,
}) {
  final asks = wanted.any((s) => s.id == GlobalShortcutsPortal.pushToTalkId);
  final known = granted.contains(GlobalShortcutsPortal.pushToTalkId);
  return (pending: asks && !known, keepKey: asks && known);
}

/// The call shortcuts Settings keeps showing as the desktop's while [wanted]
/// is being bound: those it [granted] before, which come back without a
/// dialog. Dropping them all made every row lose its desktop line and get it
/// back a moment later (Nov 16). The window leaves these keys to the desktop
/// meanwhile, so for the moment of a bind they do nothing.
Map<CallShortcut, String> callKeysWhileBinding({
  required Map<CallShortcut, String> shown,
  required List<PortalShortcut> wanted,
  required Iterable<String> granted,
}) {
  final asked = {for (final shortcut in wanted) shortcut.id};
  final known = granted.toSet();
  return {
    for (final MapEntry(key: action, value: key) in shown.entries)
      if (asked.contains(portalIdFor(action)) &&
          known.contains(portalIdFor(action)))
        action: key,
  };
}

/// What to do when the desktop refuses [asked] (or never answers): ask again
/// for what it [granted] before, and set the rest aside.
({List<PortalShortcut> retry, Set<PortalShortcut> refused}) afterRefusal({
  required List<PortalShortcut> asked,
  required Set<String> granted,
}) => (
  retry: [
    for (final shortcut in asked)
      if (granted.contains(shortcut.id)) shortcut,
  ],
  refused: {
    for (final shortcut in asked)
      if (!granted.contains(shortcut.id)) shortcut,
  },
);

/// What a person saying no to [declined] in the desktop's dialog leaves: the
/// call shortcuts among them lose their keys, since Settings says those work
/// from anywhere and a key that only works in Rift's window is not that one
/// (Nov 16). Setting keys again is a new question. Push-to-talk keeps its key,
/// which works in the window on its own, and is remembered as [refused] so the
/// dialog does not come back each launch.
({CallShortcuts calls, List<String> refused}) afterDecline({
  required CallShortcuts calls,
  required List<String> refused,
  required Iterable<PortalShortcut> declined,
}) {
  var cleared = calls;
  for (final shortcut in declined) {
    if (callShortcutForPortalId(shortcut.id) case final action?) {
      cleared = cleared.withKeys(action, null);
    }
  }
  return (
    calls: cleared,
    refused: rememberRefused(
      forgetRefused(refused, [
        for (final shortcut in declined)
          if (callShortcutForPortalId(shortcut.id) != null) shortcut.id,
      ]),
      [
        for (final shortcut in declined)
          if (callShortcutForPortalId(shortcut.id) == null) shortcut,
      ],
    ),
  );
}

/// [wanted] less what was refused ([refusalKey]s). A shortcut whose key has
/// changed since is a new question, so it stays.
List<PortalShortcut> notRefused(
  List<PortalShortcut> wanted,
  Set<String> refused,
) => [
  for (final shortcut in wanted)
    if (!refused.contains(refusalKey(shortcut))) shortcut,
];

/// A refused shortcut as it is kept: its id and the key Rift suggested, so a
/// new key asks again.
String refusalKey(PortalShortcut shortcut) =>
    '${shortcut.id}=${shortcut.preferredTrigger ?? ''}';

/// [refused] with [now] added, one entry per id: the latest key replaces an
/// older refusal of the same shortcut, so the list never grows past one per
/// shortcut.
List<String> rememberRefused(
  List<String> refused,
  Iterable<PortalShortcut> now,
) {
  final ids = {for (final shortcut in now) shortcut.id};
  return [
    for (final key in refused)
      if (!ids.contains(_idOf(key))) key,
    for (final shortcut in now) refusalKey(shortcut),
  ];
}

/// [refused] less the shortcuts the desktop has now [granted].
List<String> forgetRefused(List<String> refused, Iterable<String> granted) {
  final ids = granted.toSet();
  return [
    for (final key in refused)
      if (!ids.contains(_idOf(key))) key,
  ];
}

String _idOf(String refusalKey) => refusalKey.split('=').first;
