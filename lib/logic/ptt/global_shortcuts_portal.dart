import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:equatable/equatable.dart';

import '../helper_methods.dart';
import '../services/portal_request.dart';

/// One shortcut to ask the desktop for: an id Rift hears it by, the name the
/// desktop shows, and the key Rift suggests (null leaves it to the desktop).
class PortalShortcut extends Equatable {
  final String id;
  final String description;
  final String? preferredTrigger;

  const PortalShortcut({
    required this.id,
    required this.description,
    this.preferredTrigger,
  });

  @override
  List<Object?> get props => [id, description, preferredTrigger];
}

/// Keys outside the window on Linux, through the desktop's GlobalShortcuts
/// portal: push-to-talk and the call shortcuts (`LinuxGlobalShortcuts`).
///
/// Wayland will not let one app read keys meant for another, which is the
/// point of it — so there is no hook to install the way Windows has one. The
/// portal is the sanctioned door: the app names a shortcut and suggests a key,
/// the desktop asks the user once, and from then on reports the key going
/// down and up whichever window has focus. GNOME 48+, KDE Plasma and
/// Hyprland have it; where it is missing [bind] returns null and
/// push-to-talk works only while Rift is focused.
///
/// The desktop owns the key from here. While a session is open it grabs it
/// from every other app, so [close] must run whenever push-to-talk is turned
/// off, or a key the user bound for talking stops typing anywhere.
class GlobalShortcutsPortal {
  static const _interface = 'org.freedesktop.portal.GlobalShortcuts';

  /// Push-to-talk's id, which the desktop has stored its key under since
  /// Rift first asked for one.
  static const pushToTalkId = 'push-to-talk';

  /// Tries at binding before giving up on a desktop that keeps failing.
  ///
  /// GNOME 50.4's dialog helper (`gnome-control-center-global-shortcuts-
  /// provider`) segfaults on *every* bind, including ones that need no
  /// dialog, and the portal answers whichever way the race falls: about half
  /// the time "failed" (2) instead of the saved key. Measured 3 of 6 and 2
  /// of 6 on this machine; a retry is a fresh coin toss. The user refusing
  /// (1) is never retried — that is an answer, not a failure.
  static const _attempts = 4;
  static const _retryDelay = Duration(milliseconds: 500);
  static const _userCancelled = 1;
  static const _otherFailure = 2;

  /// GNOME answers its own dialog's Cancel with 2 as well, so a failure is
  /// retried only when it came back before anybody could have read a dialog;
  /// retrying a Cancel brought the dialog straight back (Nov 16, three times
  /// over). A bind that needs no dialog answers in well under a second.
  static const _crashAnswersWithin = Duration(seconds: 2);

  /// Whether a bind answered with [code] after [waited] is the desktop
  /// failing (try again) rather than the person saying no.
  static bool retryBind({required int code, required Duration waited}) =>
      code == _otherFailure && waited < _crashAnswersWithin;

  /// Whether a bind answered with [code] after [waited] was the person
  /// saying no in the desktop's dialog, which Rift remembers (see
  /// `LinuxGlobalShortcuts`) — rather than the desktop failing or answering
  /// late, which is asked again next launch.
  static bool declinedBy({required int code, required Duration waited}) =>
      code == _userCancelled ||
      (code == _otherFailure && waited >= _crashAnswersWithin);

  /// A portal dialog waits on a person, so this is generous.
  static const _responseTimeout = Duration(minutes: 2);

  final DBusClient _client = DBusClient.session();
  late final _requests = PortalRequests(
    _client,
    interface: _interface,
    tag: 'GlobalShortcutsPortal',
    timeout: _responseTimeout,
  );
  _Session? _current;
  int _epoch = 0;
  bool _registered = false;

  /// Opens a session and binds [shortcuts] in it.
  ///
  /// [appId] must name an installed `.desktop` file: since portal 1.20 an
  /// unsandboxed app has to say who it is before any call, and GNOME refuses
  /// an id it cannot find a desktop entry for. Returns what the desktop says
  /// each key is ("Press F9"), by id, as `triggers` — null if there is no
  /// portal, the user declined (`declined` set: see [declinedBy]), or the
  /// desktop bound none of them. An *empty* string means the
  /// shortcut is bound but has no key yet — Hyprland, for one, never asks,
  /// and waits for the user to bind it in its own config.
  ///
  /// A newer call supersedes an older one still waiting on its dialog: the
  /// older one closes only its *own* session and returns null. Letting it
  /// tidy up through [close] instead is how a declined first dialog used to
  /// take the second, accepted binding down with it.
  Future<({Map<String, String>? triggers, bool declined})> bind({
    required String appId,
    required List<PortalShortcut> shortcuts,
    required void Function(String id, int timestamp) onPress,
    required void Function(String id, int timestamp) onRelease,
    required void Function(Map<String, String> triggers) onTriggersChanged,
  }) async {
    final epoch = ++_epoch;
    await close();
    try {
      await _register(appId);
      for (var attempt = 1; ; attempt++) {
        final outcome = await _bindOnce(
          epoch: epoch,
          shortcuts: shortcuts,
          onPress: onPress,
          onRelease: onRelease,
          onTriggersChanged: onTriggersChanged,
        );
        if (!outcome.retry || attempt == _attempts || epoch != _epoch) {
          return (triggers: outcome.triggers, declined: outcome.declined);
        }
        await Future<void>.delayed(_retryDelay);
      }
    } catch (e) {
      HelperMethods.printDebug('GlobalShortcutsPortal: unavailable – $e');
      return (triggers: null, declined: false);
    }
  }

  /// One session and one bind. `retry` is set when the desktop failed rather
  /// than the user saying no — see [_attempts].
  Future<({Map<String, String>? triggers, bool retry, bool declined})>
  _bindOnce({
    required int epoch,
    required List<PortalShortcut> shortcuts,
    required void Function(String id, int timestamp) onPress,
    required void Function(String id, int timestamp) onRelease,
    required void Function(Map<String, String> triggers) onTriggersChanged,
  }) async {
    const giveUp = (triggers: null, retry: false, declined: false);
    final ids = {for (final shortcut in shortcuts) shortcut.id};
    _Session? mine;
    try {
      final created = await _requests.call(
        'CreateSession',
        (token) => [
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'session_handle_token': DBusString(_requests.nextToken('rift_ptt')),
          }),
        ],
      );
      final handle = created.results?['session_handle']?.asString();
      if (handle == null) return giveUp;
      mine = _Session(DBusObjectPath(handle));
      if (epoch != _epoch) {
        await _end(mine);
        return giveUp;
      }
      _current = mine;
      mine.signals
        ..add(_listen('Activated', mine.path, ids, onPress))
        ..add(_listen('Deactivated', mine.path, ids, onRelease))
        ..add(_listenForChanges(mine.path, onTriggersChanged));

      final asked = Stopwatch()..start();
      final bound = await _requests.call(
        'BindShortcuts',
        (token) => [
          mine!.path,
          DBusArray(DBusSignature('(sa{sv})'), [
            for (final shortcut in shortcuts)
              DBusStruct([
                DBusString(shortcut.id),
                DBusDict.stringVariant({
                  'description': DBusString(shortcut.description),
                  if (shortcut.preferredTrigger case final trigger?)
                    'preferred_trigger': DBusString(trigger),
                }),
              ]),
          ]),
          const DBusString(''),
          DBusDict.stringVariant({'handle_token': DBusString(token)}),
        ],
      );
      final triggers = _triggersOf(bound.results, ids);
      if (bound.results != null && triggers == null) {
        HelperMethods.printDebug(
          'GlobalShortcutsPortal: bound nothing – ${bound.results}',
        );
      }
      if (triggers == null || epoch != _epoch) {
        await _end(mine);
        return (
          triggers: null,
          retry: retryBind(code: bound.code, waited: asked.elapsed),
          declined: declinedBy(code: bound.code, waited: asked.elapsed),
        );
      }
      return (triggers: triggers, retry: false, declined: false);
    } catch (e) {
      if (mine != null) await _end(mine);
      rethrow;
    }
  }

  /// Ends the session, which hands the key back to every other app.
  Future<void> close() async {
    final current = _current;
    if (current != null) await _end(current);
  }

  /// Safe to call more than once for the same session, and concurrently: a
  /// failed bind ending its own session can race a newer bind closing the
  /// current one, and the second pass used to iterate a list the first had
  /// just cleared.
  Future<void> _end(_Session session) async {
    if (identical(_current, session)) _current = null;
    if (session.ended) return;
    session.ended = true;
    final signals = [...session.signals];
    session.signals.clear();
    for (final sub in signals) {
      await sub.cancel();
    }
    await _requests.closeSession(session.path);
  }

  Future<void> dispose() async {
    _epoch++;
    await close();
    await _client.close();
  }

  // ── Plumbing ──────────────────────────────────────────────────────────

  /// Once per connection: a second call is refused.
  Future<void> _register(String appId) async {
    if (_registered) return;
    _registered = true;
    await _requests.register(appId);
  }

  StreamSubscription<DBusSignal> _listen(
    String name,
    DBusObjectPath session,
    Set<String> ids,
    void Function(String id, int timestamp) handler,
  ) {
    return DBusSignalStream(
      _client,
      sender: PortalRequests.service,
      interface: _interface,
      name: name,
      path: PortalRequests.object,
    ).listen((signal) {
      // One portal carries every app's sessions; only this session's, and
      // only a shortcut it bound, is one of ours.
      if (signal.values[0] != session) return;
      final id = signal.values[1].asString();
      if (!ids.contains(id)) return;
      handler(id, signal.values[2].asUint64());
    });
  }

  /// The user changing the key in the desktop's settings arrives here, so
  /// what Rift shows follows what actually works.
  StreamSubscription<DBusSignal> _listenForChanges(
    DBusObjectPath session,
    void Function(Map<String, String> triggers) handler,
  ) {
    return DBusSignalStream(
      _client,
      sender: PortalRequests.service,
      interface: _interface,
      name: 'ShortcutsChanged',
      path: PortalRequests.object,
    ).listen((signal) {
      if (signal.values[0] != session) return;
      final triggers = _triggersOf({'shortcuts': signal.values[1]}, null);
      if (triggers != null) handler(triggers);
    });
  }

  /// Each shortcut's key as the desktop describes it, by id, keeping only
  /// [ids] when given. Null when there are none.
  static Map<String, String>? _triggersOf(
    Map<String, DBusValue>? results,
    Set<String>? ids,
  ) {
    final shortcuts = results?['shortcuts']?.asArray();
    if (shortcuts == null) return null;
    final triggers = <String, String>{};
    for (final entry in shortcuts) {
      final fields = entry.asStruct();
      final id = fields[0].asString();
      if (ids != null && !ids.contains(id)) continue;
      final props = fields[1].asStringVariantDict();
      triggers[id] = props['trigger_description']?.asString() ?? '';
    }
    return triggers.isEmpty ? null : triggers;
  }
}

/// One portal session and the signal subscriptions that belong to it.
class _Session {
  final DBusObjectPath path;
  final List<StreamSubscription<DBusSignal>> signals = [];
  bool ended = false;

  _Session(this.path);
}
