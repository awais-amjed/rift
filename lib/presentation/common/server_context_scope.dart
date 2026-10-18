import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/services/server_hub.dart';
import 'server_scope.dart';

/// [child] about the server [serverId]: its [ServerScope], and that server's
/// own cubits (`ServerContext`) above it — the roster, presence, soundboard
/// and the rest — held alive for as long as this is on screen.
///
/// What every part of the screen about a server is drawn inside: the selected
/// server's (`SelectedServerScope`), the call's (`CallServerScope`), a Manage
/// page opened on another server, and whatever those open outside their tree
/// ([ServerScope.carry]). A moved [serverId] takes the new server's before
/// letting the old one go.
class ServerContextScope extends StatefulWidget {
  final String serverId;
  final Widget child;

  const ServerContextScope({
    super.key,
    required this.serverId,
    required this.child,
  });

  @override
  State<ServerContextScope> createState() => _ServerContextScopeState();
}

class _ServerContextScopeState extends State<ServerContextScope> {
  late final ServerHub _hub;
  late ServerHold _hold;

  @override
  void initState() {
    super.initState();
    _hub = context.read<ServerHub>();
    _hold = _hub.hold(widget.serverId);
  }

  @override
  void didUpdateWidget(ServerContextScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.serverId == widget.serverId) return;
    final next = _hub.hold(widget.serverId);
    _hold.release();
    _hold = next;
  }

  @override
  void dispose() {
    _hold.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final held = _hold.context;
    return ServerScope(
      server: held.session,
      held: true,
      child: held.provide(widget.child),
    );
  }
}
