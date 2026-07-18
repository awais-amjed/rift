import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/chat_message.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../helper_methods.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'channel_chat_state.dart';
part 'channel_chat_keyring.dart';
part 'channel_chat_messages.dart';
part 'channel_chat_sweep.dart';

/// E2E chat for the selected server's text channels (ARCHITECTURE.md §4,
/// Design 2). One channel is open at a time:
///
/// - Keys: on open, the keyring is fetched and unwrapped with the local chat
///   identity; a channel with no key yet is bootstrapped (v1 generated and
///   sealed to every keyed member — first writer wins on races), and members
///   missing current-version entries are healed opportunistically.
/// - Messages: fetched as envelopes and decrypted + signature-verified
///   client-side; anything that fails verification is dropped, never shown.
/// - Live delivery: after a successful send the sender pings a Realtime
///   Broadcast topic; receivers then fetch rows after their newest id — the
///   database is the single source of truth, the ping is just a doorbell
///   (so a forged broadcast can at worst cause a fetch).
class ChannelChatCubit extends Cubit<ChannelChatState>
    with _ChatKeyringMixin, _ChatMessagesMixin, _ChatSweepMixin {
  @override
  final ServerCubit _serverCubit;
  @override
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<ServerState>? _serverSub;

  /// Server ids whose chat public key we've published this run (idempotent
  /// server-side; this just avoids a call per channel open).
  @override
  final Set<String> _publishedChatKey = {};

  /// Unwrapped channel keys for the open channel, by key version.
  @override
  final Map<int, Uint8List> _keys = {};

  /// The open channel's newest key version (0 = none yet).
  @override
  int _currentKeyVersion = 0;

  @override
  void _setCurrentKeyVersion(int version) => _currentKeyVersion = version;

  SupabaseClient? _rtClient;
  RealtimeChannel? _rtChannel;

  /// Guards against a stale async continuation writing into a newer channel.
  int _openGeneration = 0;

  StreamSubscription<VaultState>? _vaultSub;

  ChannelChatCubit({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  })  : _serverCubit = serverCubit,
        _vaultCubit = vaultCubit,
        _crypto = crypto ?? CryptoRepository(),
        super(const ChannelChatState()) {
    _serverSub = serverCubit.stream.listen(_onServerChanged);
    // The vault unlocks asynchronously at startup — chat readiness (key
    // publish + sweep) waits for the master seed.
    _vaultSub = vaultCubit.stream.listen((_) => _ensureServerChatReady());
    _ensureServerChatReady();
  }

  // ──────────────────────────────────────────────────────────
  // Open / close
  // ──────────────────────────────────────────────────────────

  Future<void> openChannel(String channelId) async {
    if (state.channelId == channelId) return;
    final generation = ++_openGeneration;
    await _teardownRealtime();

    emit(ChannelChatState(
      status: ChannelChatStatus.loading,
      channelId: channelId,
    ));

    final server = _serverCubit.state.selectedServer;
    if (server == null || server.user == null) {
      emit(state.copyWith(
        status: ChannelChatStatus.error,
        error: 'No server selected',
      ));
      return;
    }

    await _ensureChatKeyPublished(server);
    if (_isStale(generation)) return;

    final keyStatus = await _loadOrBootstrapKeyring(channelId);
    if (_isStale(generation)) return;

    if (keyStatus == _KeyringStatus.error) {
      emit(state.copyWith(
        status: ChannelChatStatus.error,
        error: 'Could not load the channel key',
      ));
      return;
    }

    _setupRealtime(server, channelId);

    if (keyStatus == _KeyringStatus.waiting) {
      // No entry sealed to us yet — another member's client will heal us.
      emit(state.copyWith(status: ChannelChatStatus.waitingForKey));
      return;
    }

    await _fetchLatest(channelId);
    if (_isStale(generation)) return;
    emit(state.copyWith(status: ChannelChatStatus.ready));
  }

  Future<void> closeChannel() async {
    _openGeneration++;
    await _teardownRealtime();
    _keys.clear();
    _currentKeyVersion = 0;
    if (!isClosed) emit(const ChannelChatState());
  }

  /// Retry entry point for the waiting/error states (UI button + doorbell).
  Future<void> retry() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    emit(const ChannelChatState());
    await openChannel(channelId);
  }

  bool _isStale(int generation) =>
      isClosed || generation != _openGeneration;

  void _onServerChanged(ServerState serverState) {
    // Switching (or losing) the server closes the open chat.
    final serverId = serverState.selectedServer?.id;
    if (state.channelId != null && serverId != _rtServerId) {
      closeChannel();
    }
    _ensureServerChatReady();
  }

  String? _rtServerId;

  // ──────────────────────────────────────────────────────────
  // Server chat readiness: key publish + sweep + doorbell
  // ──────────────────────────────────────────────────────────

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
    if (server == null || server.user == null) {
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
    unawaited(_runKeySweep());
  }

  void _setupSweepRealtime(Server server) {
    if (server.supabaseKey == null) return;
    _sweepRtClient = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _sweepRtChannel = _sweepRtClient!.channel('keysweep:${server.id}')
      ..onBroadcast(
        event: 'sweep',
        callback: (_) => _onKeySweepDoorbell(),
      )
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

  @override
  void _ringKeySweepDoorbell() {
    try {
      _sweepRtChannel?.sendBroadcastMessage(event: 'sweep', payload: {});
    } catch (_) {}
  }

  void _onKeySweepDoorbell() {
    if (isClosed) return;
    // Someone published a key or healed entries: do our share of wrapping,
    // and if we're the one waiting for access, refetch our keyring.
    unawaited(_runKeySweep());
    if (state.status == ChannelChatStatus.waitingForKey) {
      unawaited(retry());
    }
  }

  // ──────────────────────────────────────────────────────────
  // Realtime doorbell
  // ──────────────────────────────────────────────────────────

  void _setupRealtime(Server server, String channelId) {
    if (server.supabaseKey == null) return;
    _rtServerId = server.id;
    _rtClient = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _rtChannel = _rtClient!.channel('chat:$channelId')
      ..onBroadcast(
        event: 'new_message',
        callback: (_) => _onDoorbell(),
      )
      ..subscribe();
  }

  Future<void> _teardownRealtime() async {
    final channel = _rtChannel;
    final client = _rtClient;
    _rtChannel = null;
    _rtClient = null;
    _rtServerId = null;
    try {
      await channel?.unsubscribe();
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }

  /// Notify other members that a new row exists. Fire-and-forget: the row in
  /// the database is authoritative, so a lost ping only delays delivery until
  /// the next fetch.
  @override
  void _ringDoorbell() {
    try {
      _rtChannel?.sendBroadcastMessage(event: 'new_message', payload: {});
    } catch (_) {}
  }

  void _onDoorbell() {
    if (isClosed) return;
    switch (state.status) {
      case ChannelChatStatus.ready:
        unawaited(_fetchAfterLatest());
      case ChannelChatStatus.waitingForKey:
        // A member came online and may have healed our keyring entry.
        unawaited(retry());
      default:
        break;
    }
  }

  // ──────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _vaultSub?.cancel();
    await _teardownRealtime();
    await _teardownSweepRealtime();
    return super.close();
  }
}
