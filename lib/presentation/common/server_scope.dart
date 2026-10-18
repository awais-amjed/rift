import 'package:flutter/widgets.dart';

import '../../data/repositories/server_session.dart';
import 'server_context_scope.dart';

/// The server a part of the screen is about. A widget that calls a server
/// builds its `data/apis` class from [of] (or [read] in a callback), and never
/// from the selection.
///
/// The home screen puts the selected server's around everything it draws for
/// that server, and the call puts its own server's around the call: it stays
/// in the middle of the window while its member reads another server, and
/// everything it draws and does — the faces on its tiles, a right-click on
/// one of them, a move, a mute — is about the call's server. Read through the
/// selection, a tile showed the other server's idea of who that was, and a
/// moderator's "Move to" listed the other server's channels. Put there by
/// [ServerContextScope], which provides that server's cubits below it too, so
/// the roster, presence or soundboard a widget finds are that server's.
class ServerScope extends InheritedWidget {
  final ServerSession server;

  /// Whether [ServerContextScope] put this here, with the server's cubits
  /// below it, so that [carry] takes them along as well.
  final bool held;

  const ServerScope({
    super.key,
    required this.server,
    this.held = false,
    required super.child,
  });

  /// The server [context] is about.
  static ServerSession of(BuildContext context) =>
      maybeOf(context) ?? _missing(context);

  /// [of], or null outside every server's part of the screen.
  static ServerSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServerScope>()?.server;

  /// [of] for a callback, which must not register a dependency.
  static ServerSession read(BuildContext context) =>
      maybeRead(context) ?? _missing(context);

  /// [maybeOf] for a callback.
  static ServerSession? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServerScope>()?.server;

  static Never _missing(BuildContext context) => throw FlutterError(
    'No ServerScope above ${context.widget.runtimeType}: a widget that acts '
    'on a server is drawn inside the part of the screen about that server.',
  );

  /// [child] inside the scope [context] is in, for whatever is built outside
  /// the tree it opened from: a dialog or a sheet is a route of its own, a
  /// menu an overlay entry, and either would otherwise find no server at all.
  /// Hands on the server's cubits too, which is what the scope's widgets
  /// read, held alive for as long as what carried them is open.
  static Widget carry(BuildContext context, Widget child) =>
      carrier(context)(child);

  /// [carry], read now and applied later: for a builder that runs after
  /// [context] may be gone, as a phone's submenu replacing its menu does.
  static Widget Function(Widget child) carrier(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ServerScope>();
    if (scope == null) return (child) => child;
    final server = scope.server;
    if (!scope.held) {
      return (child) => ServerScope(server: server, child: child);
    }
    return (child) =>
        ServerContextScope(serverId: server.serverId, child: child);
  }

  @override
  bool updateShouldNotify(ServerScope oldWidget) =>
      oldWidget.server != server || oldWidget.held != held;
}
