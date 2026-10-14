import 'dart:async';

import 'package:dbus/dbus.dart';
import '../helper_methods.dart';
import '../services/portal_request.dart';

/// Push-to-talk outside the window on Linux, through the desktop's
/// GlobalShortcuts portal.
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
  static const _shortcutId = 'push-to-talk';

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
  static const _otherFailure = 2;

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

  /// Opens a session and binds the push-to-talk shortcut.
  ///
  /// [appId] must name an installed `.desktop` file: since portal 1.20 an
  /// unsandboxed app has to say who it is before any call, and GNOME refuses
  /// an id it cannot find a desktop entry for. Returns what the desktop says
  /// the key is ("Press F9"), or null if there is no portal or the user
  /// declined. An *empty* string means the session is open but no key is
  /// assigned yet — Hyprland, for one, never asks, and waits for the user to
  /// bind the shortcut in its own config.
  ///
  /// A newer call supersedes an older one still waiting on its dialog: the
  /// older one closes only its *own* session and returns null. Letting it
  /// tidy up through [close] instead is how a declined first dialog used to
  /// take the second, accepted binding down with it.
  Future<String?> bind({
    required String appId,
    required String? preferredTrigger,
    required void Function(int timestamp) onPress,
    required void Function(int timestamp) onRelease,
    required void Function(String trigger) onTriggerChanged,
  }) async {
    final epoch = ++_epoch;
    await close();
    try {
      await _register(appId);
      for (var attempt = 1; ; attempt++) {
        final outcome = await _bindOnce(
          epoch: epoch,
          preferredTrigger: preferredTrigger,
          onPress: onPress,
          onRelease: onRelease,
          onTriggerChanged: onTriggerChanged,
        );
        if (!outcome.retry || attempt == _attempts || epoch != _epoch) {
          return outcome.trigger;
        }
        await Future<void>.delayed(_retryDelay);
      }
    } catch (e) {
      HelperMethods.printDebug('GlobalShortcutsPortal: unavailable – $e');
      return null;
    }
  }

  /// One session and one bind. `retry` is set when the desktop failed rather
  /// than the user saying no — see [_attempts].
  Future<({String? trigger, bool retry})> _bindOnce({
    required int epoch,
    required String? preferredTrigger,
    required void Function(int timestamp) onPress,
    required void Function(int timestamp) onRelease,
    required void Function(String trigger) onTriggerChanged,
  }) async {
    const giveUp = (trigger: null, retry: false);
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
        ..add(_listen('Activated', mine.path, onPress))
        ..add(_listen('Deactivated', mine.path, onRelease))
        ..add(_listenForChanges(mine.path, onTriggerChanged));

      final bound = await _requests.call(
        'BindShortcuts',
        (token) => [
          mine!.path,
          DBusArray(DBusSignature('(sa{sv})'), [
            DBusStruct([
              const DBusString(_shortcutId),
              DBusDict.stringVariant({
                'description': const DBusString('Push to talk'),
                if (preferredTrigger != null)
                  'preferred_trigger': DBusString(preferredTrigger),
              }),
            ]),
          ]),
          const DBusString(''),
          DBusDict.stringVariant({'handle_token': DBusString(token)}),
        ],
      );
      final trigger = _triggerOf(bound.results);
      if (bound.results != null && trigger == null) {
        HelperMethods.printDebug(
          'GlobalShortcutsPortal: bound nothing – ${bound.results}',
        );
      }
      if (trigger == null || epoch != _epoch) {
        await _end(mine);
        return (trigger: null, retry: bound.code == _otherFailure);
      }
      return (trigger: trigger, retry: false);
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
    void Function(int timestamp) handler,
  ) {
    return DBusSignalStream(
      _client,
      sender: PortalRequests.service,
      interface: _interface,
      name: name,
      path: PortalRequests.object,
    ).listen((signal) {
      // One portal carries every app's sessions; only ours, and only our
      // shortcut, is a push-to-talk key.
      if (signal.values[0] != session) return;
      if (signal.values[1].asString() != _shortcutId) return;
      handler(signal.values[2].asUint64());
    });
  }

  /// The user changing the key in the desktop's settings arrives here, so
  /// what Rift shows follows what actually works.
  StreamSubscription<DBusSignal> _listenForChanges(
    DBusObjectPath session,
    void Function(String trigger) handler,
  ) {
    return DBusSignalStream(
      _client,
      sender: PortalRequests.service,
      interface: _interface,
      name: 'ShortcutsChanged',
      path: PortalRequests.object,
    ).listen((signal) {
      if (signal.values[0] != session) return;
      final trigger = _triggerOf({'shortcuts': signal.values[1]});
      if (trigger != null) handler(trigger);
    });
  }

  static String? _triggerOf(Map<String, DBusValue>? results) {
    final shortcuts = results?['shortcuts']?.asArray();
    if (shortcuts == null) return null;
    for (final entry in shortcuts) {
      final fields = entry.asStruct();
      if (fields[0].asString() != _shortcutId) continue;
      final props = fields[1].asStringVariantDict();
      return props['trigger_description']?.asString() ?? '';
    }
    return null;
  }
}

/// One portal session and the signal subscriptions that belong to it.
class _Session {
  final DBusObjectPath path;
  final List<StreamSubscription<DBusSignal>> signals = [];
  bool ended = false;

  _Session(this.path);
}
