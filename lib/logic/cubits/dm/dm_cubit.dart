import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rift_crypto/rift_crypto.dart';
import 'package:supabase/supabase.dart' show RealtimeSubscribeStatus;

import '../../../data/apis/attachments_api.dart';
import '../../../data/apis/dm_calls_api.dart';
import '../../../data/apis/dms_api.dart';
import '../../../data/apis/members_api.dart';
import '../../../data/apis/moderation_api.dart';
import '../../../data/apis/pins_polls_api.dart';
import '../../../data/apis/reactions_api.dart';
import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_call.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/equality_props.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/message_cache_slot.dart';
import '../../../data/classes/notice.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/dm_link_state.dart';
import '../../../data/enums/dm_policy.dart';
import '../../../data/repositories/attachment_repository.dart';
import '../../../data/repositories/blob/blob_sink.dart';
import '../../../data/repositories/server_session.dart';
import '../../../data/repositories/session_repository.dart';
import '../../helper_methods.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/attachment_loader.dart';
import '../../services/before_quit.dart';
import '../../services/broadcast_payload.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_message_ops.dart';
import '../../services/dm_refusal.dart';
import '../../services/edit_refusal.dart';
import '../../services/link_preview_fetcher.dart';
import '../../services/message_cache.dart';
import '../../services/new_message_notifier.dart';
import '../../services/notification_ids.dart';
import '../../services/outbox.dart';
import '../../services/pin_ops.dart';
import '../../services/quote_lookup.dart';
import '../../services/reaction_ops.dart';
import '../../services/saved_conversation.dart';
import '../../services/sealed_open.dart';
import '../../services/server_realtime.dart';
import '../../services/server_topics.dart';
import '../vault/vault_cubit.dart';

part 'dm_call_log.dart';
part 'dm_conversations.dart';
part 'dm_decrypt.dart';
part 'dm_edit.dart';
part 'dm_history.dart';
part 'dm_pins.dart';
part 'dm_quick_send.dart';
part 'dm_reactions.dart';
part 'dm_realtime.dart';
part 'dm_requests.dart';
part 'dm_send.dart';
part 'dm_set_aside.dart';
part 'dm_state.dart';

/// E2E direct messages between members of one server
/// (ARCHITECTURE.md §4, Design 1 — encrypt to identity): the one [showServer]
/// last named, which is the selected one — `ServerHub` says when it moves.
/// Everything here reads that server, never the selection, so work started on
/// one server finishes there however quickly the selection moves on.
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
        _DmCallLogMixin,
        _DmRealtimeMixin,
        _DmSetAsideMixin,
        _DmQuickSendMixin {
  @override
  final SessionRepository _session;

  /// The server this cubit is set up for, which every call it makes goes to.
  /// Before one is, there is none, and a call made then answers
  /// [ServerSession.gone].
  ServerSession get _readyServer => _session.on(_readyServerId ?? '');

  @override
  ModerationApi get _moderation => ModerationApi(_readyServer);
  @override
  MembersApi get _members => MembersApi(_readyServer);
  @override
  PinsPollsApi get _pinsPolls => PinsPollsApi(_readyServer);
  @override
  DmsApi get _dms => DmsApi(_readyServer);
  @override
  DmCallsApi get _calls => DmCallsApi(_readyServer);
  @override
  ReactionsApi get _reactions => ReactionsApi(_readyServer);
  @override
  AttachmentsApi get _attachments => AttachmentsApi(_readyServer);
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<void>? _serverSub;
  StreamSubscription<VaultState>? _vaultSub;

  /// Cached DM keys per peer (derivation is a DH + HMAC — cheap, but not
  /// free, and used per message).
  @override
  final Map<String, Uint8List> _dmKeys = {};

  /// The peer chat key each entry in [_dmKeys] was worked out from. A peer
  /// who publishes a new one gets a new DM key, so a cached key is only good
  /// while the listed one still matches it.
  @override
  final Map<String, String> _dmKeySources = {};

  /// The server [showServer] named, and the one set up for it once its user
  /// and the vault are there.
  String? _wantedServerId;
  @override
  String? _readyServerId;

  /// Counts [_onServerChanged]s, so a switch still letting the last server go
  /// when a newer one starts gives way to it. Without this a quick A, B, C
  /// finished B's setup last: B's DMs listed while C was on screen, and C's
  /// realtime joins were never let go.
  int _switches = 0;

  /// The server these DMs are on, or null before one is set up.
  String? get serverId => _readyServerId;

  @override
  Server? get _server =>
      _readyServerId == null ? null : _session.serverById(_readyServerId!);

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
  Server? get _savedServer => _server;

  @override
  String? get _seed => _vaultCubit.state.masterSeed;

  DmCubit({
    required SessionRepository session,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  }) : _session = session,
       _vaultCubit = vaultCubit,
       _crypto = crypto ?? CryptoRepository(),
       super(const DmState()) {
    _serverSub = session.changes.listen((_) => _onServerChanged());
    _vaultSub = vaultCubit.stream.listen((_) => _onServerChanged());
    _onServerChanged();
    BeforeQuit.instance.add(saveAsLeft);
  }

  @override
  void onChange(Change<DmState> change) {
    super.onChange(change);
    _followCallLog(change.nextState);
  }

  // ── Server lifecycle ────────────────────────────────────

  /// List [serverId]'s DMs, closing whatever was open on another server.
  void showServer(String? serverId) {
    _wantedServerId = serverId;
    unawaited(_onServerChanged());
  }

  Future<void> _onServerChanged() async {
    final switchId = ++_switches;
    final wanted = _wantedServerId;
    final server = wanted == null ? null : _session.serverById(wanted);
    if (server == null ||
        !server.admitsUs ||
        _vaultCubit.state.masterSeed == null) {
      if (_readyServerId != null) await _reset();
      return;
    }
    if (server.id == _readyServerId) return;
    await _reset();
    if (isClosed || switchId != _switches) return;
    _readyServerId = server.id;
    _setupRealtime(server);
    unawaited(refreshLists());
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

  /// Resolves once [serverId]'s conversation list has come in, after a
  /// server switch. A message notification names the person but not the key
  /// to read them with, and the list is where that key is: [readyFor] alone
  /// resolved before the list arrived, so a press on a DM from another
  /// server opened the DM page and not the conversation.
  Future<void> listedFor(String serverId) async {
    bool listed() => _readyServerId == serverId && _conversationsListed;
    if (listed()) return;
    await stream
        .firstWhere((_) => listed())
        .timeout(const Duration(seconds: 5), onTimeout: () => state);
  }

  Future<void> _reset() async {
    // Whatever was open is saved to the server it belongs to — read now,
    // before the reset forgets which one that was.
    unawaited(_saved.flush(leaving: true));
    _readyServerId = null;
    _conversationsListed = false;
    _forgetSetAside();
    _dmKeys.clear();
    _dmKeySources.clear();
    _outbox.clear();
    _notifier.reset();
    await _teardownRealtime();
    if (!isClosed) emit(const DmState());
  }

  // ── Crypto helpers ──────────────────────────────────────

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
    if (cached != null &&
        (peerChatKey == null || _dmKeySources[peerId] == peerChatKey)) {
      return cached;
    }
    if (peerChatKey == null) return null;
    final server = _server;
    if (server == null || _vaultCubit.state.masterSeed == null) return null;

    final identity = await _vaultCubit.getChatIdentityForHost(_hostOf(server));
    final key = await _crypto.deriveDmKey(
      myKeyPair: identity.keyPair,
      theirPublicKey: CryptoRepository.fromBase64(peerChatKey),
    );
    _dmKeys[peerId] = key;
    _dmKeySources[peerId] = peerChatKey;
    return key;
  }

  // ── Notifications ───────────────────────────────────────

  @override
  void _notifyFromConversations(List<DmConversation> conversations) {
    final serverId = _readyServerId;
    _notifier.scan(
      conversations,
      titleFor: (c) => c.peerName,
      payloadFor: (c) => serverId == null
          ? null
          : ConversationNotificationPayload.serverDm(
              serverId,
              c.peerId,
            ).encode(),
    );
  }

  // ── Lifecycle ───────────────────────────────────────────

  /// Save what is open as *left*, without closing it: the app quitting
  /// ([BeforeQuit]), or another surface taking the screen while it stays
  /// open behind. Leaving is when this device's own sends reach the copy.
  Future<void> saveAsLeft() => _saved.flush(leaving: true);

  @override
  Future<void> close() async {
    BeforeQuit.instance.remove(saveAsLeft);
    await _saved.flush(leaving: true);
    _saved.dispose();
    await _serverSub?.cancel();
    await _vaultSub?.cancel();
    await _teardownRealtime();
    return super.close();
  }
}
