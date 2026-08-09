import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
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

  const ServerMembersState({
    this.serverId,
    this.members,
    this.loading = false,
    this.error,
  });
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
/// (`004_realtime.sql`), and Realtime re-checks 002's policies per subscriber,
/// so a change only reaches members of that user's own server. The event is
/// used as a doorbell rather than a delta: the roster is refetched through
/// [ServerCubit.listMembers] so it arrives shaped like the first load and gets
/// the token refresh that call already handles. That also covers renames, new
/// avatars, permission changes and bans, not just joins.
class ServerMembersCubit extends Cubit<ServerMembersState> {
  /// One join writes a row and then updates it (chat key, avatar); coalesce the
  /// burst into a single refetch.
  static const _coalesce = Duration(milliseconds: 250);

  final ServerCubit _serverCubit;
  StreamSubscription<ServerState>? _serverSub;

  SupabaseClient? _client;
  RealtimeChannel? _channel;
  String? _serverId;
  String? _token;
  Timer? _debounce;

  /// Guards against a slow fetch landing after a newer one, or after a switch.
  int _loadId = 0;

  ServerMembersCubit({required ServerCubit serverCubit})
    : _serverCubit = serverCubit,
      super(const ServerMembersState()) {
    _serverSub = serverCubit.stream.listen(_sync);
    _sync(serverCubit.state);
  }

  void _sync(ServerState serverState) {
    final server = serverState.selectedServer;
    if (server == null || server.supabaseKey == null || server.user == null) {
      if (_serverId == null) return;
      _teardown();
      if (!isClosed) emit(const ServerMembersState());
      return;
    }

    if (server.id != _serverId) {
      _teardown();
      _serverId = server.id;
      _token = server.token;
      if (!isClosed) {
        emit(ServerMembersState(serverId: server.id, loading: true));
      }
      unawaited(refresh());
    } else if (server.token != _token) {
      // Silent re-auth rotated the JWT. Realtime has to be re-pointed at it or
      // the subscription dies with the token it was opened on.
      _token = server.token;
      _client?.realtime.setAuth(server.token);
    }

    // Hydrated tokens read as near-expiry at startup, and subscribing with one
    // opens a connection that is already dead. The refresh that `listMembers`
    // triggers comes back through here as a token change, and we subscribe then.
    if (_channel == null && !server.isTokenNearExpiry) _subscribe(server);
  }

  void _subscribe(Server server) {
    final client = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    // RLS has to see `auth.uid()`, so both transports carry the member's JWT.
    client.headers = {
      'apikey': server.supabaseKey!,
      'Authorization': 'Bearer ${server.token}',
    };
    client.realtime.setAuth(server.token);
    _client = client;
    _channel = client.channel('members:${server.id}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'users',
        callback: (_) => _scheduleRefresh(),
      )
      ..subscribe();
  }

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(_coalesce, () => unawaited(refresh()));
  }

  /// Refetch the roster for the selected server. A failure keeps the members we
  /// already have — a dropped connection shouldn't blank the sidebar.
  Future<void> refresh() async {
    final serverId = _serverId;
    if (serverId == null) return;
    final loadId = ++_loadId;

    final result = await _serverCubit.listMembers();
    if (isClosed || loadId != _loadId || serverId != _serverId) return;

    emit(
      ServerMembersState(
        serverId: serverId,
        members: result.success ? result.members : state.members,
        error: result.success ? null : result.error,
      ),
    );
  }

  void _teardown() {
    _debounce?.cancel();
    _debounce = null;
    _serverId = null;
    _token = null;
    _loadId++;

    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;
    unawaited(() async {
      try {
        await channel?.unsubscribe();
        client?.removeAllChannels();
        await client?.dispose();
      } catch (_) {}
    }());
  }

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    _teardown();
    return super.close();
  }
}
