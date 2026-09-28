import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_call.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/message_cache_slot.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/dm_link_state.dart';
import '../../../data/enums/dm_policy.dart';
import '../../helper_methods.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/broadcast_payload.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_message_ops.dart';
import '../../services/dm_refusal.dart';
import '../../services/edit_refusal.dart';
import '../../services/link_preview_fetcher.dart';
import '../../services/new_message_notifier.dart';
import '../../services/outbox.dart';
import '../../services/pin_ops.dart';
import '../../services/quote_lookup.dart';
import '../../services/reaction_ops.dart';
import '../../services/saved_conversation.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'dm_call_log.dart';
part 'dm_conversations.dart';
part 'dm_decrypt.dart';
part 'dm_edit.dart';
part 'dm_history.dart';
part 'dm_pins.dart';
part 'dm_reactions.dart';
part 'dm_requests.dart';
part 'dm_send.dart';
part 'dm_state.dart';

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
        _DmReactionsMixin,
        _DmPinsMixin,
        _DmRequestsMixin,
        _DmCallLogMixin {
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

  /// Our own topic, where the database says a DM arrived, changed or was
  /// reacted to, and where peers say they are typing.
  RealtimeLease? _inbox;

  /// Who the open conversation is with — the one we tell we are typing.
  String? _typingPeerId;
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

  /// The open conversation's saved copy. On the class because the history
  /// mixin draws and feeds it and the edit mixin takes deleted rows out of it
  /// (CODE_STYLE §5). A DM keeps nothing beside its rows: its key is worked
  /// out on this device from the two people's chat keys.
  @override
  final SavedConversation _saved = SavedConversation();

  @override
  Server? get _savedServer => _serverCubit.state.selectedServer;

  @override
  String? get _seed => _vaultCubit.state.masterSeed;

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

  @override
  void onChange(Change<DmState> change) {
    super.onChange(change);
    _followCallLog(change.nextState);
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
    unawaited(refreshRequests());
    unawaited(refreshBlocks());
  }

  /// Resolves once this cubit has moved over to [serverId], after a server
  /// switch. A conversation opened before then would be wiped by the switch
  /// finishing behind it — which is what answering a call from another server
  /// does, selecting that server and opening the caller at once.
  Future<void> readyFor(String serverId) async {
    if (_readyServerId == serverId) return;
    await stream
        .firstWhere((_) => _readyServerId == serverId)
        .timeout(const Duration(seconds: 5), onTimeout: () => state);
  }

  Future<void> _reset() async {
    // Whatever was open is saved to the server it belongs to — read now,
    // before the reset forgets which one that was.
    unawaited(_saved.flush(leaving: true));
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

  /// The database rings us itself — a DM arrives the same way
  /// whether a person or a bot sent it, and nobody has to remember to say so.
  /// What it carries is ids; the row is what's true, and we go and read it.
  void _setupRealtime(Server server) {
    final user = server.user;
    if (user == null) return;
    _inbox = _serverCubit.realtime.join(server, ServerTopics.user(user.id))
      ?..onBroadcast(ServerEvent.dm, (_) => _onDoorbell())
      ..onBroadcast(ServerEvent.dmChanged, _onChangeDoorbell)
      ..onBroadcast(ServerEvent.dmReaction, _onReactionDoorbell)
      ..onBroadcast(ServerEvent.dmPin, _onPinDoorbell)
      ..onBroadcast(ServerEvent.dmRequests, (_) => _onRequestsDoorbell())
      ..onBroadcast(ServerEvent.blocks, (_) => _onBlocksDoorbell())
      // A call rang, was answered or ended; the open conversation's log may
      // be the one it belongs to.
      ..onBroadcast(ServerEvent.dmCalls, (_) {
        if (state.openPeerId != null) unawaited(refreshCallLog());
      })
      ..onBroadcast(ServerEvent.typing, _onTyping);
  }

  Future<void> _teardownRealtime() async {
    final inbox = _inbox;
    _inbox = null;
    _typingPeerId = null;
    await inbox?.release();
  }

  @override
  void _joinPeerTopic(String peerId) {
    _leavePeerTopic();
    _typingPeerId = peerId;
    unawaited(refreshOpenLinkState());
  }

  @override
  void _leavePeerTopic() {
    // Leaving the open conversation also clears any pending typing indicator.
    _typingTimer?.cancel();
    _typingTimer = null;
    _lastTypingSent = null;
    _typingPeerId = null;
  }

  void _onChangeDoorbell(Map<String, dynamic> payload) {
    if (isClosed || state.chatStatus != DmChatStatus.ready) return;
    final messageId = BroadcastPayload.stringOf(payload, 'message_id');
    if (messageId != null) unawaited(refreshMessage(messageId));
    // The conversation list shows a preview of the newest message, which an
    // edit or delete can change.
    unawaited(refreshConversations());
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
      // A reply to our request is its acceptance.
      if (state.openLinkState != DmLinkState.open) {
        unawaited(refreshOpenLinkState());
      }
    }
  }

  /// A request arrived, or another of our devices answered one.
  void _onRequestsDoorbell() {
    if (isClosed) return;
    unawaited(refreshRequests());
    unawaited(refreshConversations());
    if (state.openPeerId != null) unawaited(refreshOpenLinkState());
  }

  void _onBlocksDoorbell() {
    if (isClosed) return;
    unawaited(refreshBlocks());
    unawaited(refreshRequests());
  }

  // ──────────────────────────────────────────────────────────
  // Typing indicators
  // ──────────────────────────────────────────────────────────

  /// Tell the open peer we're typing (throttled). Sent to their topic without
  /// joining it — nobody but them may — so it goes over HTTP.
  void notifyTyping() {
    final now = DateTime.now();
    if (_lastTypingSent != null &&
        now.difference(_lastTypingSent!) < _typingThrottle) {
      return;
    }
    final server = _serverCubit.state.selectedServer;
    final user = server?.user;
    final peerId = _typingPeerId;
    if (server == null || user == null || peerId == null) return;
    _lastTypingSent = now;
    unawaited(
      _serverCubit.realtime.ring(
        server,
        ServerTopics.user(peerId),
        ServerEvent.typing,
        {'from': user.id, 'name': user.displayName},
      ),
    );
  }

  void _onTyping(Map<String, dynamic> payload) {
    if (isClosed) return;
    final from = BroadcastPayload.stringOf(payload, 'from');
    // Only surface typing for the conversation the user currently has open.
    if (from == null || from != state.openPeerId) return;
    // The name this device already has for them, not the one in the event:
    // any member may send on this topic, so a name read from it is whatever
    // the sender chose to put there.
    final name = state.openPeerName;
    if (name == null) return;

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
    await _saved.flush(leaving: true);
    _saved.dispose();
    await _serverSub?.cancel();
    await _vaultSub?.cancel();
    _typingTimer?.cancel();
    await _teardownRealtime();
    return super.close();
  }
}
