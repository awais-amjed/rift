import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
import '../../services/server_table_watcher.dart';
import '../server/server_cubit.dart';

// ── State ────────────────────────────────────────────────────────────────────

class ServerMembersState {
  /// Which server [members] belongs to. Null when no server is selected.
  final String? serverId;

  /// Null until the first load for [serverId] lands — which is what the
  /// sidebar shows a spinner for. An empty list means a server with no other
  /// members, not a pending load.
  final List<ServerMember>? members;

  final bool loading;
  final String? error;

  ServerMembersState({
    this.serverId,
    this.members,
    this.loading = false,
    this.error,
  });

  /// Members by user id, built once per state.
  late final Map<String, ServerMember> byId = {
    for (final member in members ?? const <ServerMember>[]) member.id: member,
  };

  /// The current display name for [userId].
  ///
  /// [fallback] is the copy frozen into a LiveKit token or a presence payload,
  /// used only for somebody this roster hasn't got — the seconds between them
  /// joining a call and our refetch landing. Everything that renders a name
  /// goes through here, so a rename shows up in one place rather than three.
  String nameFor(String userId, String fallback) =>
      byId[userId]?.displayName ?? fallback;
}

// ── Cubit ────────────────────────────────────────────────────────────────────

/// The selected server's member roster, kept live.
///
/// Presence (who is *online*) has always been realtime; membership (who is
/// *here at all*) was fetched once per server and cached until you switched
/// away, so somebody who joined while you were looking never appeared —
/// [MemberRoster.split] has no row to attach their presence to, and drops them.
///
/// `users` is in the realtime publication for exactly this reason
/// (`004_realtime.sql`), and [ServerTableWatcher] turns a row event into a
/// refetch through [ServerCubit.listMembers]. That covers renames, new avatars,
/// permission changes and bans as well as joins.
class ServerMembersCubit extends Cubit<ServerMembersState> {
  final ServerCubit _serverCubit;
  late final ServerTableWatcher _watcher;

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  int _loadId = 0;

  void Function()? _onSelfModerationChanged;

  /// Called when the local user's own mute/deafen state changes — see
  /// [_notifySelfModeration].
  void setOnSelfModerationChanged(void Function() callback) =>
      _onSelfModerationChanged = callback;

  ServerMembersCubit({required ServerCubit serverCubit})
    : _serverCubit = serverCubit,
      super(ServerMembersState()) {
    _watcher = ServerTableWatcher(
      serverCubit: serverCubit,
      table: 'users',
      onChanged: () => unawaited(refresh()),
      onServerChanged: _onServerChanged,
    );
  }

  void _onServerChanged(Server? server) {
    if (isClosed) return;
    _loadId++;
    if (server == null) {
      emit(ServerMembersState());
      return;
    }
    emit(ServerMembersState(serverId: server.id, loading: true));
    unawaited(refresh());
  }

  /// Refetch the roster for the selected server. A failure keeps the members we
  /// already have — a dropped connection shouldn't blank the sidebar.
  Future<void> refresh() async {
    final serverId = _watcher.serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final result = await _serverCubit.listMembers();
    if (isClosed || loadId != _loadId || serverId != _watcher.serverId) return;

    final previous = state;
    final next = ServerMembersState(
      serverId: serverId,
      members: result.success ? result.members : state.members,
      error: result.success ? null : result.error,
    );
    emit(next);
    _notifySelfModeration(previous, next);
  }

  /// A member's own mute/deafen state is baked into the LiveKit token they
  /// hold, which outlives the change by the best part of an hour. When ours
  /// moves, whoever is listening has to drop that token — otherwise a muted
  /// member gets their old permissions back just by rejoining.
  void _notifySelfModeration(
    ServerMembersState previous,
    ServerMembersState next,
  ) {
    final myId = _serverCubit.state.selectedServer?.user?.id;
    if (myId == null) return;

    // No prior row means this is the first load for the server, not a change.
    final before = previous.byId[myId];
    final after = next.byId[myId];
    if (before == null || after == null) return;

    if (before.isMuted != after.isMuted ||
        before.isDeafened != after.isDeafened) {
      _onSelfModerationChanged?.call();
    }
  }

  @override
  Future<void> close() async {
    await _watcher.dispose();
    return super.close();
  }
}
