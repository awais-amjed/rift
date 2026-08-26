part of 'channel_chat_cubit.dart';

/// Getting a server ready for chat, once per server per run: publish our chat
/// key, subscribe the key-sweep topic, run the first sweep.
///
/// Split out of the cubit hub because it answers a different question from the
/// rest of it. Everything else here is about *the open channel*; this is about
/// the server behind it, and it runs on construction, on a server change and on
/// a vault unlock — none of which involve a channel at all.
///
/// [_ringKeySweepDoorbell] deliberately stays on the class: two mixins declare
/// it abstractly, and CODE_STYLE §5 has the class be the meeting point for
/// those rather than a sibling mixin.
mixin _ChatReadyMixin
    on Cubit<ChannelChatState>, _ChatKeyringMixin, _ChatSweepMixin {
  /// Implemented by the cubit class.
  Future<void> retry();

  /// The server we've completed chat setup for this run (published our chat
  /// key, subscribed the key-sweep topic, ran the initial sweep).
  String? _readyServerId;
  SupabaseClient? _sweepRtClient;
  RealtimeChannel? _sweepRtChannel;

  /// Idempotent: brings chat readiness in line with the selected server.
  /// Requires a logged-in server user and an unlocked vault; called on
  /// construction, server change, and vault unlock.
  Future<void> _ensureServerChatReady() async {
    final server = _serverCubit.state.selectedServer;
    // A ban counts as having no server here. Without this the setup still ran
    // — publishing a key, sweeping, subscribing — and every call quietly
    // failed against RLS, but `_readyServerId` was set all the same. Lifting
    // the ban then changed nothing, because readiness was already "done": the
    // channel list came back and opening a channel did nothing at all. Being
    // unready is the honest state, and it is what makes the unban re-run this.
    if (server == null || server.user == null || server.user!.isBanned) {
      await _teardownSweepRealtime();
      _readyServerId = null;
      return;
    }
    if (_vaultCubit.state.masterSeed == null) return;
    if (server.id == _readyServerId) return;
    _readyServerId = server.id;

    await _teardownSweepRealtime();
    _setupSweepRealtime(server);

    final newlyPublished = await _ensureChatKeyPublished(server);
    // A newly keyed member: tell online members to wrap for us right away.
    if (newlyPublished) _ringKeySweepDoorbell();
    // If the publish didn't stick (locked vault, network/auth failure), leave
    // readiness unset so the next server/vault event retries the whole setup.
    if (!_publishedChatKey.contains(server.id)) _readyServerId = null;
    unawaited(_runKeySweep());
    // Housekeeping, not chat: applies the operator's retention settings and
    // removes attachment blobs whose messages are gone. It rides along here
    // because this is the app's once-per-server-ready hook, and because a
    // server whose members never open it never gets swept — the pg_cron job
    // trims message rows but cannot touch storage.
    unawaited(_serverCubit.sweepAttachments());
  }

  void _setupSweepRealtime(Server server) {
    if (server.supabaseKey == null) return;
    _sweepRtClient = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _sweepRtChannel = _sweepRtClient!.channel('keysweep:${server.id}')
      ..onBroadcast(event: 'sweep', callback: (_) => _onKeySweepDoorbell())
      ..subscribe();
  }

  Future<void> _teardownSweepRealtime() async {
    final channel = _sweepRtChannel;
    final client = _sweepRtClient;
    _sweepRtChannel = null;
    _sweepRtClient = null;
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }

  void _onKeySweepDoorbell() {
    if (isClosed) return;
    // Someone published a key or healed entries: do our share of wrapping,
    // and if we're the one waiting for access, refetch our keyring.
    unawaited(_runKeySweep());
    if (state.status == ChannelChatStatus.waitingForKey ||
        state.status == ChannelChatStatus.readOnly) {
      unawaited(retry());
      return;
    }
    // Already reading this channel: the doorbell may be announcing a rotation
    // rather than a heal, and the new version has to be picked up or this
    // client keeps sealing with a key the others have moved off.
    final channelId = state.channelId;
    if (channelId != null) unawaited(_absorbNewKeyVersions(channelId));
  }
}
