import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/repositories/server_session.dart';
import '../../logic/cubits/server_members/server_members_cubit.dart';

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
/// moderator's "Move to" listed the other server's channels. Below one of
/// these, the [ServerMembersCubit] found is that server's roster too.
class ServerScope extends InheritedWidget {
  final ServerSession server;

  const ServerScope({super.key, required this.server, required super.child});

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
  /// Hands on the roster too, which is what the scope's widgets read.
  static Widget carry(BuildContext context, Widget child) =>
      carrier(context)(child);

  /// [carry], read now and applied later: for a builder that runs after
  /// [context] may be gone, as a phone's submenu replacing its menu does.
  static Widget Function(Widget child) carrier(BuildContext context) {
    final server = maybeRead(context);
    if (server == null) return (child) => child;
    final members = context.read<ServerMembersCubit>();
    return (child) => ServerScope(
      server: server,
      child: BlocProvider<ServerMembersCubit>.value(
        value: members,
        child: child,
      ),
    );
  }

  @override
  bool updateShouldNotify(ServerScope oldWidget) => oldWidget.server != server;
}
