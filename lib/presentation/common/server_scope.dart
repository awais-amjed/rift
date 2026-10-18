import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/server_members/server_members_cubit.dart';

/// The server a part of the screen is about, when that is not simply the
/// selected one.
///
/// The call is the case it exists for. It stays in the middle of the window
/// while its member reads another server, and everything it draws and does —
/// the faces on its tiles, a right-click on one of them, a move, a mute — is
/// about the call's server. Read through the selection, a tile showed the
/// other server's idea of who that was, and a moderator's "Move to" listed
/// the other server's channels. Below one of these, [of] says which server,
/// and the [ServerMembersCubit] found is that server's roster.
///
/// A null [serverId] is the selected server, which is what every `serverId`
/// parameter of a `data/apis` call already takes it to mean.
class ServerScope extends InheritedWidget {
  final String? serverId;

  const ServerScope({super.key, required this.serverId, required super.child});

  /// The server [context] is about, or null for the selected one.
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ServerScope>()?.serverId;

  /// [of] for a callback, which must not register a dependency.
  static String? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ServerScope>()?.serverId;

  /// [child] inside the scope [context] is in, for whatever is built outside
  /// the tree it opened from: a menu is an overlay entry, a full-screen
  /// stream a route of its own, and either would otherwise read the selected
  /// server again. Hands on the roster too, which is what the scope's
  /// widgets read.
  static Widget carry(BuildContext context, Widget child) =>
      carrier(context)(child);

  /// [carry], read now and applied later: for a builder that runs after
  /// [context] may be gone, as a phone's submenu replacing its menu does.
  static Widget Function(Widget child) carrier(BuildContext context) {
    final serverId = context
        .getInheritedWidgetOfExactType<ServerScope>()
        ?.serverId;
    if (serverId == null) return (child) => child;
    final members = context.read<ServerMembersCubit>();
    return (child) => ServerScope(
      serverId: serverId,
      child: BlocProvider<ServerMembersCubit>.value(
        value: members,
        child: child,
      ),
    );
  }

  @override
  bool updateShouldNotify(ServerScope oldWidget) =>
      oldWidget.serverId != serverId;
}
