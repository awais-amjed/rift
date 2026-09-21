import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

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
  /// declined.
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
  }) async {
    final epoch = ++_epoch;
    await close();
    _Session? mine;
    try {
      await _register(appId);

      final created = await _request(
        'CreateSession',
        (token) => [
          DBusDict.stringVariant({
            'handle_token': DBusString(token),
            'session_handle_token': DBusString('rift_ptt_${_tokens++}'),
          }),
        ],
      );
      final handle = created?['session_handle']?.asString();
      if (handle == null) return null;
      mine = _Session(DBusObjectPath(handle));
      if (epoch != _epoch) {
        await _end(mine);
        return null;
      }
      _current = mine;
      mine.signals
        ..add(_listen('Activated', mine.path, onPress))
        ..add(_listen('Deactivated', mine.path, onRelease));

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
      final trigger = _triggerOf(bound);
      if (bound != null && trigger == null) {
        debugPrint('GlobalShortcutsPortal: bound nothing – $bound');
      }
      if (trigger == null || epoch != _epoch) {
        await _end(mine);
        return null;
      }
      return trigger;
    } catch (e) {
      debugPrint('GlobalShortcutsPortal: unavailable – $e');
      if (mine != null) await _end(mine);
      return null;
    }
  }

  /// Ends the session, which hands the key back to every other app.
  Future<void> close() async {
    final current = _current;
    if (current != null) await _end(current);
  }

  Future<void> _end(_Session session) async {
    if (identical(_current, session)) _current = null;
    for (final sub in session.signals) {
      await sub.cancel();
    }
    session.signals.clear();
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
      debugPrint('GlobalShortcutsPortal: close failed – $e');
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
    await _client.callMethod(
      destination: _service,
      path: _object,
      interface: 'org.freedesktop.host.portal.Registry',
      name: 'Register',
      values: [DBusString(appId), DBusDict.stringVariant({})],
      replySignature: DBusSignature(''),
    );
    _registered = true;
  }

  /// Calls a portal method that answers later, on a Request object, and
  /// waits for that answer. Null unless the response code is 0 (success).
  ///
  /// The Request's path is derived from our bus name and a token we choose,
  /// so the subscription goes in *before* the call — the answer can arrive
  /// before the call itself returns.
  Future<Map<String, DBusValue>?> _request(
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
        debugPrint('GlobalShortcutsPortal: $method answered $code');
        return null;
      }
      return signal.values[1].asStringVariantDict();
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

  _Session(this.path);
}
