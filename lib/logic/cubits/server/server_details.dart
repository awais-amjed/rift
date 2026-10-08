part of 'server_cubit.dart';

/// Reading a server's details back into the list, and what happens when the
/// server no longer knows us.
mixin _ServerDetailsMixin on Cubit<ServerState> {
  SessionRepository get _session;

  /// Implemented by [ServerCubit]: land a whole `get_server_details()` reply.
  void applyServerDetails(
    String serverId,
    ServerDetails details, {
    String? token,
  });
  void removeServer(String serverId);
  void noteServerGone({required String supabaseUrl, required String id});

  /// Drop a server that answered as though it had never heard of us, and say
  /// so.
  void _forgetGoneServer(Server server) {
    // Before the removal, because the removal is what schedules the backup
    // that would otherwise bring it straight back.
    noteServerGone(supabaseUrl: server.supabaseUrl, id: server.id);
    removeServer(server.id);
    emit(
      state.copyWith(
        notice: Notice.info(
          'No longer on ${server.name}',
          'The server was deleted, or you were removed from it.',
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Server details
  // ──────────────────────────────────────────────────────────

  /// The selected server's re-reads, coalesced: see [refreshServerDetails].
  late final CoalescedRefresh<({bool success, String? error})> _details =
      CoalescedRefresh(_fetchServerDetails);

  /// Refresh the channel list and other details for [serverId], or for the
  /// selected server.
  ///
  /// Coalesced, because one structural change reaches a member more than
  /// once — the database announces it, and the member who made it also
  /// re-reads straight after their own write. See [CoalescedRefresh] for why
  /// the second read still happens rather than being dropped.
  ///
  /// A named server other than the selected one is read straight away: it is
  /// a settings page acting on it, once, not the stream of doorbells the
  /// selected one hears.
  Future<({bool success, String? error})> refreshServerDetails({
    String? serverId,
  }) {
    if (serverId == null || serverId == state.selectedServer?.id) {
      return _details();
    }
    final server = state.serverById(serverId);
    if (server == null) {
      return Future.value((success: false, error: _session.noTarget(serverId)));
    }
    return _fetchDetailsOf(server);
  }

  Future<({bool success, String? error})> _fetchServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }
    return _fetchDetailsOf(server);
  }

  Future<({bool success, String? error})> _fetchDetailsOf(Server server) async {
    final response = await _session.callFor(
      server,
      (token) => _session.repository.getServerDetails(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );

    // The server's row is invisible to somebody it no longer knows — our own
    // row is what scopes every read — so "not found" from a server we were on
    // yesterday means it was deleted, or we were removed. Either way there is
    // nothing left here to refresh, and keeping the rail chip would leave a
    // server nobody can leave. The same note the login path takes: without
    // it the auto-backup this removal triggers merges the cloud's copy back in.
    if (!response.success && response.error == ServerDb.serverGone) {
      _forgetGoneServer(server);
      return (success: false, error: response.error);
    }

    if (response.success) {
      final data = response.data as Map<String, dynamic>;
      applyServerDetails(server.id, ServerDetails.fromJson(data));
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to refresh server details',
      );
    }
  }
}
