import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/server.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../helper_methods.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'dm_state.dart';
part 'dm_messages.dart';

/// E2E direct messages between members of the selected server
/// (ARCHITECTURE.md §4, Design 1 — encrypt to identity).
///
/// The DM key is derived pairwise (X25519 DH between the two members' chat
/// identities) — no keyring, no waiting states: if the peer has published a
/// chat key, the conversation just works. Live delivery uses a per-user
/// Realtime doorbell topic (`dm:<serverId>:<userId>`); the database row is
/// authoritative, the ping is a doorbell exactly like channel chat.
class DmCubit extends Cubit<DmState> with _DmMessagesMixin {
  @override
  final ServerCubit _serverCubit;
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<ServerState>? _serverSub;
  StreamSubscription<VaultState>? _vaultSub;

  /// Cached DM keys per peer (derivation is a DH + HMAC — cheap, but not
  /// free, and used per message).
  @override
  final Map<String, Uint8List> _dmKeys = {};

  SupabaseClient? _rtClient;
  RealtimeChannel? _peerTopic;
  String? _readyServerId;

  DmCubit({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  })  : _serverCubit = serverCubit,
        _vaultCubit = vaultCubit,
        _crypto = crypto ?? CryptoRepository(),
        super(const DmState()) {
    _serverSub = serverCubit.stream.listen((_) => _onServerChanged());
    _vaultSub = vaultCubit.stream.listen((_) => _onServerChanged());
    _onServerChanged();
  }

  // ──────────────────────────────────────────────────────────
  // Server lifecycle
  // ──────────────────────────────────────────────────────────

  Future<void> _onServerChanged() async {
    final server = _serverCubit.state.selectedServer;
    if (server == null ||
        server.user == null ||
        _vaultCubit.state.masterSeed == null) {
      if (_readyServerId != null) await _reset();
      return;
    }
    if (server.id == _readyServerId) return;
    await _reset();
    _readyServerId = server.id;
    _setupRealtime(server);
    unawaited(refreshConversations());
  }

  Future<void> _reset() async {
    _readyServerId = null;
    _dmKeys.clear();
    await _teardownRealtime();
    if (!isClosed) emit(const DmState());
  }

  // ──────────────────────────────────────────────────────────
  // Crypto helpers
  // ──────────────────────────────────────────────────────────

  /// Signed context for a DM conversation — order-independent, so both
  /// parties derive the same id and envelopes can't cross conversations.
  static String conversationContext(String userA, String userB) {
    final ids = [userA, userB]..sort();
    return 'dm:${ids[0]}:${ids[1]}';
  }

  String _hostOf(Server server) => Uri.parse(server.supabaseUrl).host;

  /// The Ed25519 signing identity for this server (message signatures).
  @override
  Future<ServerIdentity> _vaultIdentityFor(Server server) =>
      _vaultCubit.getIdentityForHost(_hostOf(server), version: server.keyVersion);

  @override
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey) async {
    final cached = _dmKeys[peerId];
    if (cached != null) return cached;
    if (peerChatKey == null) return null;
    final server = _serverCubit.state.selectedServer;
    if (server == null || _vaultCubit.state.masterSeed == null) return null;

    final identity = await _vaultCubit.getChatIdentityForHost(_hostOf(server));
    final key = await _crypto.deriveDmKey(
      myKeyPair: identity.keyPair,
      theirPublicKey: CryptoRepository.fromBase64(peerChatKey),
    );
    _dmKeys[peerId] = key;
    return key;
  }

  // ──────────────────────────────────────────────────────────
  // Realtime doorbells
  // ──────────────────────────────────────────────────────────

  void _setupRealtime(Server server) {
    if (server.supabaseKey == null || server.user == null) return;
    _rtClient = SupabaseClient(server.supabaseUrl, server.supabaseKey!);
    _rtClient!.channel('dm:${server.id}:${server.user!.id}')
      ..onBroadcast(event: 'new_dm', callback: (_) => _onDoorbell())
      ..subscribe();
  }

  Future<void> _teardownRealtime() async {
    final client = _rtClient;
    _rtClient = null;
    _peerTopic = null;
    try {
      client?.removeAllChannels();
      await client?.dispose();
    } catch (_) {}
  }

  /// Joins the open peer's doorbell topic so sends can ring them.
  @override
  void _joinPeerTopic(String peerId) {
    final server = _serverCubit.state.selectedServer;
    if (_rtClient == null || server == null) return;
    _leavePeerTopic();
    _peerTopic = _rtClient!.channel('dm:${server.id}:$peerId')..subscribe();
  }

  @override
  void _leavePeerTopic() {
    final topic = _peerTopic;
    _peerTopic = null;
    if (topic != null) {
      try {
        _rtClient?.removeChannel(topic);
      } catch (_) {}
    }
  }

  @override
  void _ringPeerDoorbell() {
    try {
      _peerTopic?.sendBroadcastMessage(event: 'new_dm', payload: {});
    } catch (_) {}
  }

  void _onDoorbell() {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(_fetchAfterLatest());
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
    return super.close();
  }
}
