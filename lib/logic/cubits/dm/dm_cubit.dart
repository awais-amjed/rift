import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/api_response.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../services/link_preview_fetcher.dart';
import '../../../data/classes/server.dart';
import 'package:rift_crypto/rift_crypto.dart';
import '../../helper_methods.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/broadcast_payload.dart';
import '../../services/chat_message_ops.dart';
import '../../services/notification_service.dart';
import '../../services/outbox.dart';
import '../../services/reaction_ops.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'dm_state.dart';
part 'dm_conversations.dart';
part 'dm_decrypt.dart';
part 'dm_history.dart';
part 'dm_send.dart';
part 'dm_edit.dart';
part 'dm_reactions.dart';

/// E2E direct messages between members of the selected server
/// (ARCHITECTURE.md §4, Design 1 — encrypt to identity).
///
/// The DM key is derived pairwise (X25519 DH between the two members' chat
/// identities) — no keyring, no waiting states: if the peer has published a
/// chat key, the conversation just works. Live delivery uses a per-user
/// Realtime doorbell topic (`dm:<serverId>:<userId>`); the database row is
/// authoritative, the ping is a doorbell exactly like channel chat.
class DmCubit extends Cubit<DmState>
    with
        _DmDecryptMixin,
        _DmConversationsMixin,
        _DmHistoryMixin,
        _DmSendMixin,
        _DmEditMixin,
        _DmReactionsMixin {
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

  /// Diffs conversation snapshots to raise notifications for new DMs.
  final NewMessageNotifier _notifier = NewMessageNotifier();

  /// Sends that failed on the way out, waiting to be retried.
  ///
  /// On the class because two mixins need it: the send mixin holds and takes,
  /// the history mixin restores and drops (CODE_STYLE §5). Cleared with the
  /// rest of the state on a server switch — a message meant for one server's
  /// member has nowhere to go on another.
  @override
  final Outbox _outbox = Outbox();

  /// Expiry timer + rate-limit for the typing indicator.
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  static const _typingThrottle = Duration(seconds: 2);
  static const _typingTimeout = Duration(seconds: 5);

  DmCubit({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  }) : _serverCubit = serverCubit,
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
    _outbox.clear();
    _notifier.reset();
    _typingTimer?.cancel();
    _typingTimer = null;
    _lastTypingSent = null;
    await _teardownRealtime();
    if (!isClosed) emit(const DmState());
  }

  // ──────────────────────────────────────────────────────────
  // Crypto helpers
  // ──────────────────────────────────────────────────────────

  /// Signed context for a DM conversation — order-independent, so both
  /// parties derive the same id and envelopes can't cross conversations.
  static String conversationContext(String userA, String userB) =>
      MessageEnvelope.conversationContext(userA, userB);

  String _hostOf(Server server) => Uri.parse(server.supabaseUrl).host;

  /// The Ed25519 signing identity for this server (message signatures).
  @override
  Future<ServerIdentity> _vaultIdentityFor(Server server) =>
      _vaultCubit.getIdentityForHost(
        _hostOf(server),
        serverId: server.id,
        version: server.keyVersion,
      );

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
      ..onBroadcast(event: 'message_changed', callback: _onChangeDoorbell)
      ..onBroadcast(event: 'typing', callback: _onTyping)
      ..onBroadcast(event: 'reaction', callback: _onReactionDoorbell)
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
    // Leaving the open conversation also clears any pending typing indicator.
    _typingTimer?.cancel();
    _typingTimer = null;
    _lastTypingSent = null;
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

  /// Tell the peer that a message was edited or deleted. Which of the two, and
  /// what it now says, is deliberately left out — they re-read the row, so a
  /// forged ping can only cost them a request.
  @override
  void _ringChangeDoorbell(String messageId) {
    try {
      _peerTopic?.sendBroadcastMessage(
        event: 'message_changed',
        payload: {'message_id': messageId},
      );
    } catch (_) {}
  }

  void _onChangeDoorbell(Map<String, dynamic> payload) {
    if (isClosed || state.chatStatus != DmChatStatus.ready) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) unawaited(refreshMessage(messageId));
    // The conversation list shows a preview of the newest message, which an
    // edit or delete can change.
    unawaited(refreshConversations());
  }

  /// Tell the peer which message's reactions changed, so they refresh that one
  /// rather than every message they have loaded.
  @override
  void _ringReactionDoorbell(String messageId) {
    try {
      _peerTopic?.sendBroadcastMessage(
        event: 'reaction',
        payload: {'message_id': messageId},
      );
    } catch (_) {}
  }

  /// A ring without a message id is an older client; fall back to refreshing
  /// everything loaded.
  void _onReactionDoorbell(Map<String, dynamic> payload) {
    if (isClosed) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) {
      unawaited(refreshReactionsFor(messageId));
    } else {
      unawaited(refreshReactions());
    }
  }

  void _onDoorbell() {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(_fetchAfterLatest());
    }
  }

  // ──────────────────────────────────────────────────────────
  // Typing indicators
  // ──────────────────────────────────────────────────────────

  /// Broadcast to the open peer's inbox that we're typing (throttled).
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingThrottle) {
      return;
    }
    final user = _serverCubit.state.selectedServer?.user;
    if (user == null || _peerTopic == null) return;
    _lastTypingSent = now;
    try {
      _peerTopic!.sendBroadcastMessage(
        event: 'typing',
        payload: {'from': user.id, 'name': user.displayName},
      );
    } catch (_) {}
  }

  void _onTyping(Map<String, dynamic> payload) {
    if (isClosed) return;
    final from = BroadcastPayload.stringOf(payload, 'from');
    final name = BroadcastPayload.stringOf(payload, 'name');
    // Only surface typing for the conversation the user currently has open.
    if (from == null || name == null || from != state.openPeerId) return;

    _typingTimer?.cancel();
    _typingTimer = Timer(_typingTimeout, () {
      if (!isClosed) emit(state.copyWith(clearTyping: true));
    });
    if (state.typingPeerName != name) {
      emit(state.copyWith(typingPeerName: name));
    }
  }

  @override
  void _onOpenPeerMessage() {
    _typingTimer?.cancel();
    _typingTimer = null;
    if (!isClosed && state.typingPeerName != null) {
      emit(state.copyWith(clearTyping: true));
    }
  }

  @override
  void _notifyFromConversations(List<DmConversation> conversations) {
    _notifier.scan(conversations, titleFor: (c) => c.peerName);
  }

  // ──────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _serverSub?.cancel();
    await _vaultSub?.cancel();
    _typingTimer?.cancel();
    await _teardownRealtime();
    return super.close();
  }
}
