import 'dart:async';

import 'package:dbus/dbus.dart';
import '../helper_methods.dart';

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
  static const _service = 'org.freedesktop.portal.Desktop';
  static const _interface = 'org.freedesktop.portal.GlobalShortcuts';
  static final _object = DBusObjectPath('/org/freedesktop/portal/desktop');
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
  _Session? _current;
  int _epoch = 0;
  bool _registered = false;
  int _tokens = 0;

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
      final created = await _request(
        'CreateSession',
        (token) => [
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'session_handle_token': DBusString('rift_ptt_${_tokens++}'),
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

      final bound = await _request(
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
    try {
      await _client.callMethod(
        destination: _service,
        path: session.path,
        interface: 'org.freedesktop.portal.Session',
        name: 'Close',
        replySignature: DBusSignature(''),
      );
    } catch (e) {
      // Already closed by the portal, e.g. after a declined dialog.
      HelperMethods.printDebug('GlobalShortcutsPortal: close failed – $e');
    }
  }

  Future<void> dispose() async {
    _epoch++;
    await close();
    await _client.close();
  }

  // ── Plumbing ──────────────────────────────────────────────────────────

  /// Tells the portal which app this is. Once per connection: a second call
  /// is refused.
  Future<void> _register(String appId) async {
    if (_registered) return;
    // Tried once per connection, and never fatal. A sandboxed app (Flatpak,
    // Snap) is already known to the portal by its sandbox and may have this
    // refused, and a portal older than 1.20 has no Registry at all — in both
    // cases the calls that follow work without it. Only a GNOME host app
    // truly needs it, and there the refusal shows up on those calls anyway.
    _registered = true;
    try {
      await _client.callMethod(
        destination: _service,
        path: _object,
        interface: 'org.freedesktop.host.portal.Registry',
        name: 'Register',
        values: [DBusString(appId), DBusDict.stringVariant({})],
        replySignature: DBusSignature(''),
      );
    } catch (e) {
      HelperMethods.printDebug(
        'GlobalShortcutsPortal: Register refused, going on – $e',
      );
    }
  }

  /// Calls a portal method that answers later, on a Request object, and
  /// waits for that answer. `results` is null unless the code is 0
  /// (success).
  ///
  /// The Request's path is derived from our bus name and a token we choose,
  /// so the subscription goes in *before* the call — the answer can arrive
  /// before the call itself returns.
  Future<({int code, Map<String, DBusValue>? results})> _request(
    String method,
    List<DBusValue> Function(String token) args,
  ) async {
    final token = 'rift_${_tokens++}';
    final sender = _client.uniqueName.substring(1).replaceAll('.', '_');
    final answer = Completer<DBusSignal>();
    final sub =
        DBusSignalStream(
          _client,
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
          path: DBusObjectPath(
            '/org/freedesktop/portal/desktop/request/$sender/$token',
          ),
        ).listen((signal) {
          if (!answer.isCompleted) answer.complete(signal);
        });
    try {
      await _client.callMethod(
        destination: _service,
        path: _object,
        interface: _interface,
        name: method,
        values: args(token),
        replySignature: DBusSignature('o'),
      );
      final signal = await answer.future.timeout(_responseTimeout);
      final code = signal.values[0].asUint32();
      if (code != 0) {
        // 1 is the user saying no, 2 anything else the desktop refused.
        HelperMethods.printDebug(
          'GlobalShortcutsPortal: $method answered $code',
        );
        return (code: code, results: null);
      }
      return (code: 0, results: signal.values[1].asStringVariantDict());
    } finally {
      await sub.cancel();
    }
  }

  StreamSubscription<DBusSignal> _listen(
    String name,
    DBusObjectPath session,
    void Function(int timestamp) handler,
  ) {
    return DBusSignalStream(
      _client,
      sender: _service,
      interface: _interface,
      name: name,
      path: _object,
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
      sender: _service,
      interface: _interface,
      name: 'ShortcutsChanged',
      path: _object,
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
