import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../logic/cubits/server/server_cubit.dart';
import '../../logic/services/server_hub.dart';
import 'server_context_scope.dart';
import 'server_scope.dart';

/// The selected server's [ServerScope] and cubits, round the whole app.
///
/// The one place the selection becomes a server for widgets: below here they
/// ask the scope which server they are about, and what is about another server
/// — the call, Manage server opened from the rail for any server — provides
/// its own over it. Round the navigator rather than the home screen, so a
/// page or a dialog that carries no scope of its own is about the selected
/// server, as everything on screen around it is.
class SelectedServerScope extends StatelessWidget {
  final Widget child;

  const SelectedServerScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final selectedId = context.select<ServerCubit, String?>(
      (cubit) => cubit.state.selectedServerId,
    );
    // No scope with nothing selected — an action on a server has none to
    // act on, and says so — but the server's cubits, empty, for the parts of
    // the screen drawn either way.
    if (selectedId == null) {
      return context.read<ServerHub>().none.provide(child);
    }
    return ServerContextScope(serverId: selectedId, child: child);
  }
}
