import 'dart:async';

import 'package:dbus/dbus.dart';

import '../helper_methods.dart';

/// Calls to one of the desktop's portals (`org.freedesktop.portal.*`) whose
/// answer comes later, on a Request object: push-to-talk's GlobalShortcuts
/// and a window share's ScreenCast.
class PortalRequests {
  static const service = 'org.freedesktop.portal.Desktop';
  static final object = DBusObjectPath('/org/freedesktop/portal/desktop');

  final DBusClient client;

  /// The portal's interface, `org.freedesktop.portal.GlobalShortcuts`.
  final String interface;

  /// What the log calls this portal's user.
  final String tag;

  /// How long an answer may take. A dialog waits on a person.
  final Duration timeout;

  int _tokens = 0;

  PortalRequests(
    this.client, {
    required this.interface,
    required this.tag,
    required this.timeout,
  });

  /// Tells the portal which app this is, once per connection: a second call
  /// is refused.
  ///
  /// Never fatal. A sandboxed app (Flatpak, Snap) is already known to the
  /// portal by its sandbox and may have this refused, and a portal older
  /// than 1.20 has no Registry at all — in both cases the calls that follow
  /// work without it. A GNOME host app needs it for GlobalShortcuts, and
  /// for ScreenCast wherever a pick is saved: GTK registers the app's main
  /// connection, where libwebrtc asks, and a pick saved for an unnamed one
  /// is not found from there.
  Future<void> register(String appId) async {
    try {
      await client.callMethod(
        destination: service,
        path: object,
        interface: 'org.freedesktop.host.portal.Registry',
        name: 'Register',
        values: [DBusString(appId), DBusDict.stringVariant({})],
        replySignature: DBusSignature(''),
      );
    } catch (e) {
      HelperMethods.printDebug('$tag: Register refused, going on – $e');
    }
  }

  /// A token for a request or a session, unique on this connection.
  String nextToken(String prefix) => '${prefix}_${_tokens++}';

  /// Calls [method] and waits for its answer. `results` is null unless the
  /// code is 0 (success).
  ///
  /// The Request's path is derived from our bus name and a token we choose,
  /// so the subscription goes in *before* the call — the answer can arrive
  /// before the call itself returns.
  Future<({int code, Map<String, DBusValue>? results})> call(
    String method,
    List<DBusValue> Function(String token) args,
  ) async {
    final token = nextToken('rift');
    // A connection has no name until its first call, and the path needs it.
    if (client.uniqueName.isEmpty) await client.ping();
    final sender = client.uniqueName.substring(1).replaceAll('.', '_');
    final answer = Completer<DBusSignal>();
    final sub =
        DBusSignalStream(
          client,
          interface: 'org.freedesktop.portal.Request',
          name: 'Response',
          path: DBusObjectPath(
            '/org/freedesktop/portal/desktop/request/$sender/$token',
          ),
        ).listen((signal) {
          if (!answer.isCompleted) answer.complete(signal);
        });
    try {
      await client.callMethod(
        destination: service,
        path: object,
        interface: interface,
        name: method,
        values: args(token),
        replySignature: DBusSignature('o'),
      );
      final signal = await answer.future.timeout(timeout);
      final code = signal.values[0].asUint32();
      if (code != 0) {
        // 1 is the user saying no, 2 anything else the desktop refused.
        HelperMethods.printDebug('$tag: $method answered $code');
        return (code: code, results: null);
      }
      return (code: 0, results: signal.values[1].asStringVariantDict());
    } finally {
      await sub.cancel();
    }
  }

  /// Ends a portal session. Never fatal: the portal may have closed it
  /// already, after a declined dialog for one.
  Future<void> closeSession(DBusObjectPath session) async {
    try {
      await client.callMethod(
        destination: service,
        path: session,
        interface: 'org.freedesktop.portal.Session',
        name: 'Close',
        replySignature: DBusSignature(''),
      );
    } catch (e) {
      HelperMethods.printDebug('$tag: close failed – $e');
    }
  }
}
