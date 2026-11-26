part of 'server_cubit.dart';

mixin _ServerCrudMixin on Cubit<ServerState> {
  void Function()? get _onServersChanged;
  SecureStorageRepository get _storage;
  SessionRepository get _session;

  /// Registering this device on a server, as the list and the FCM token
  /// change.
  PushApi _pushOn(String serverId);
  OwnershipApi _ownershipOn(String serverId);

  Future<({bool success, String? error})> refreshServerDetails({
    required String serverId,
  });

  // ── CRUD ──────────────────────────────────────────────────

  /// The server already listed under [serverId] at another address than
  /// [supabaseUrl], which a join must not add beside it.
  ///
  /// A server chooses its own id, and everything here finds a server by its
  /// id alone: a second row with the same one had its token, its socket and
  /// its removal shared with the first. So a server answering with the id of
  /// one already on the list — or the same server joined again by another
  /// address — is refused rather than added.
  Server? listedElsewhere({
    required String supabaseUrl,
    required String serverId,
  }) {
    final listed = state.serverById(serverId);
    if (listed == null || Server.sameUrl(listed.supabaseUrl, supabaseUrl)) {
      return null;
    }
    return listed;
  }

  /// Puts a server just joined on the list and selects it, or null when
  /// [listedElsewhere] refuses it (said in a notice).
  ///
  /// One already on the list at this address — an invite tapped to a server
  /// you are on, answered as a rejoin — takes the place of the row it had,
  /// rather than a second chip beside it.
  ///
  /// [detailsRead] says [serverDetails] is the member's own
  /// `get_server_details`, read by the join, so it is not read again here.
  Server? addServer(
    String supabaseUrl,
    String token,
    Map<String, dynamic> serverDetails, {
    bool detailsRead = false,
  }) {
    final joined = Server.fromJoin(supabaseUrl, token, serverDetails);
    final clash = listedElsewhere(
      supabaseUrl: supabaseUrl,
      serverId: joined.id,
    );
    if (clash != null) {
      emit(
        state.copyWith(
          notice: Notice.error(
            'You are already on ${clash.name} at '
            '${Uri.tryParse(clash.supabaseUrl)?.host ?? clash.supabaseUrl}, '
            'and ${Uri.tryParse(supabaseUrl)?.host ?? supabaseUrl} answered '
            'as the same server.',
          ),
        ),
      );
      return null;
    }
    final listed = state.serverById(joined.id);
    // Kept under the address it was listed at, which its saved conversations
    // are filed under.
    final newServer = listed == null
        ? joined
        : Server.fromJoin(listed.supabaseUrl, token, serverDetails);
    // Joining again is the answer to having been removed, so the note that
    // kept it out of the rail has to go with it.
    _clearServerGone(supabaseUrl: newServer.supabaseUrl, id: newServer.id);
    // And its conversations may be saved on this device again.
    MessageCacheSlot.scopesOfServer(
      newServer.supabaseUrl,
      newServer.id,
    ).forEach(MessageCache.instance.reopenScope);
    final updated = listed == null
        ? [...state.servers, newServer]
        : [for (final s in state.servers) s.id == newServer.id ? newServer : s];
    emit(state.copyWith(servers: updated, selectedServerId: newServer.id));
    _onServersChanged?.call();
    // The FCM token listener only fires when the token changes, and joining is
    // not that — so a server joined mid-session would otherwise go unregistered
    // until the next launch.
    unawaited(_pushOn(newServer.id).registerDevice());
    if (!detailsRead) _readJoinedServer(newServer.id);
    return newServer;
  }

  /// Read a server just joined through `get_server_details`, unless the
  /// join did (self-host 1.9.1 answers `register` without a context).
  ///
  /// An older `register`'s reply is built on the service role, which knows the three
  /// cached booleans but not the permission bits (`my_permissions()`
  /// describes the caller, and the caller there is the service role) nor
  /// each channel's own. Kept as it came, a new admin's bits read as zero,
  /// and every page that asks them — a channel's Permissions, roles,
  /// invites — drew its controls disabled until something read the server
  /// again: a switch away and back, or a restart. Found Nov 15 after a
  /// console update, which it had nothing to do with.
  void _readJoinedServer(String serverId) =>
      unawaited(refreshServerDetails(serverId: serverId));

  /// Move the server at [from] so that it ends up at [to].
  ///
  /// Both are indices into the final list, which is what `onReorderItem`
  /// hands over — the older `onReorder` gave an insertion point into the
  /// unshortened one and left the off-by-one to the caller.
  ///
  /// The clock is a plain +1 rather than a timestamp: this device's clock is
  /// already the highest it has seen, because every merge adopts the higher
  /// of the two. So the order chosen *after* learning of another device's
  /// order outranks it, and two orders at the same clock are decided by the
  /// first device to merge them, which steps its own past the other's — see
  /// [BackupMerge.union].
  void reorderServers(int from, int to) {
    final count = state.servers.length;
    if (from < 0 || from >= count || to < 0 || to >= count || from == to) {
      return;
    }

    final updated = [...state.servers];
    updated.insert(to, updated.removeAt(from));
    emit(state.copyWith(servers: updated, orderClock: state.orderClock + 1));
    _onServersChanged?.call();
  }

  /// Servers this session has been told it is no longer on.
  ///
  /// Keyed the way [BackupMerge] keys a manifest entry, because the whole
  /// point is to be able to answer for one. Not persisted: it exists to stop
  /// the cloud copy resurrecting a server *between* the removal and the
  /// upload that follows it. After that upload the cloud no longer lists it,
  /// so there is nothing left to remember.
  final Set<String> _goneKeys = {};

  void noteServerGone({required String supabaseUrl, required String id}) {
    _goneKeys.add(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));
  }

  bool isServerGone({required String supabaseUrl, required String id}) =>
      _goneKeys.contains(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));

  /// Rejoining clears the note, or the merge would keep dropping a server the
  /// user has just deliberately joined again.
  void _clearServerGone({required String supabaseUrl, required String id}) {
    _goneKeys.remove(BackupMerge.keyFor(supabaseUrl: supabaseUrl, id: id));
  }

  /// Leave [server]: ask it to take us off its list (`leave_server`), then
  /// forget it here.
  ///
  /// The owner is not asked — the server refuses them, and their dialog has
  /// already said that leaving only forgets it here. Nor is a server too old
  /// to have the call. One that does not answer is forgotten all the same,
  /// since otherwise a server that is gone for good could never be left, and
  /// the notice says it may still list us. Only a refusal keeps it.
  ///
  /// Noted gone before anything is asked: the leave rings the server, and a
  /// re-read landing before the removal would draw it shut for a moment, or
  /// the cloud's copy would bring it back.
  Future<LeaveOutcome> leaveServer(Server server) async {
    noteServerGone(supabaseUrl: server.supabaseUrl, id: server.id);
    final isOwner = server.user?.permissions.isOwner ?? false;
    final result = isOwner
        ? (outcome: LeaveOutcome.unsupported, error: null)
        : await _ownershipOn(server.id).leaveServer();

    switch (result.outcome) {
      case LeaveOutcome.refused:
        _clearServerGone(supabaseUrl: server.supabaseUrl, id: server.id);
        emit(state.copyWith(notice: Notice.error(result.error!)));
      case LeaveOutcome.unreachable:
        removeServer(server.id);
        emit(
          state.copyWith(
            notice: Notice.info(
              'Left ${server.name} on this device',
              "The server didn't answer, so it may still list you as a "
                  'member.',
            ),
          ),
        );
      case LeaveOutcome.left || LeaveOutcome.unsupported:
        removeServer(server.id);
    }
    return result.outcome;
  }

  void removeServer(String serverId) {
    // Before the server leaves the list, while there is still a session to say
    // it with: a device that stays registered on a server you have left goes
    // on being woken for it. Not awaited — leaving must not wait on a server
    // that has already stopped answering.
    unawaited(_pushOn(serverId).forgetDevice());
    _forgetSavedConversations(serverId);
    _session.members.forget(serverId);
    final updated = state.servers.where((s) => s.id != serverId).toList();
    String? newSelectedId = state.selectedServerId;
    if (newSelectedId == serverId) {
      newSelectedId = updated.isNotEmpty ? updated.first.id : null;
    }
    emit(
      state.copyWith(
        servers: updated,
        selectedServerId: newSelectedId,
        clearSelectedServerId: newSelectedId == null,
      ),
    );
    _onServersChanged?.call();
  }

  /// The copies of this server's channels and DMs kept on this device (see
  /// [MessageCache]). Leaving a server takes them with it: what was saved to
  /// draw a conversation faster must not outlive being able to open it.
  void _forgetSavedConversations(String serverId) {
    final server = state.servers.where((s) => s.id == serverId).firstOrNull;
    if (server == null) return;
    final scopes = MessageCacheSlot.scopesOfServer(
      server.supabaseUrl,
      server.id,
    ).toList();
    unawaited(() async {
      final seed = await _storage.getMasterSeed();
      if (seed == null) return;
      for (final scope in scopes) {
        await MessageCache.instance.forgetScope(seed, scope);
      }
    }());
  }
}
