import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase/supabase.dart';

import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_member.dart';
import '../../../data/classes/panel_block.dart';
import '../../../data/enums/message_origin.dart';
import '../../../data/enums/notification_level.dart';
import 'package:rift_crypto/rift_crypto.dart';
import '../../helper_methods.dart';
import '../../services/broadcast_payload.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_failure.dart';
import '../../services/channel_keyring.dart';
import '../../services/key_sweep_doorbell.dart';
import '../../services/bot_command.dart';
import '../../services/chat_message_ops.dart';
import '../../services/chat_notice.dart';
import '../../services/mention_name_cache.dart';
import '../../services/mentions.dart';
import '../../services/notification_service.dart';
import '../../services/outbox.dart';
import '../../services/reaction_ops.dart';
import '../../services/window_focus_service.dart';
import '../server/server_cubit.dart';
import '../vault/vault_cubit.dart';

part 'channel_chat_state.dart';
part 'channel_chat_notify.dart';
part 'channel_chat_ready.dart';
part 'channel_chat_rows.dart';
part 'channel_chat_history.dart';
part 'channel_chat_send.dart';
part 'channel_chat_panels.dart';
part 'channel_chat_edit.dart';
part 'channel_chat_reactions.dart';
part 'channel_chat_realtime.dart';
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
    with
        _ChannelChatRowsMixin,
        _ChannelChatHistoryMixin,
        _ChannelChatSendMixin,
        _ChannelChatPanelsMixin,
        _ChannelChatEditMixin,
        _ChannelChatReactionsMixin,
        _ChannelChatRealtimeMixin,
        _ChatSweepMixin,
        _ChatReadyMixin,
        _ChatNotifyMixin {
  @override
  final ServerCubit _serverCubit;

  /// The roster, for turning an `@name` into the user id the server rings.
  ///
  /// Resolution happens on the way out rather than on the way in because only
  /// the sender's client can do it at all: the server cannot read the message
  /// to find the names, and the recipients cannot be told which of them was
  /// meant without being told first.
  /// What `@names` in the open channel resolve to, and which have been asked.
  ///
  /// Cleared with the channel by [_resetTo]. Both halves live in one object so
  /// that a reset cannot drop the answers and keep the questions — see
  /// [MentionNameCache].
  @override
  final MentionNameCache _mentionCache = MentionNameCache();

  @override
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<ServerState>? _serverSub;

  /// The open channel's keys.
  ///
  /// A service rather than a mixin since voice needs the same bootstrap for the
  /// same channels — LiveKit's frame cryptor wants the very bytes this holds.
  /// Two copies of key bootstrap would be two things that can disagree about
  /// which version is current, and that disagreement presents as a room where
  /// some people can read each other and some cannot.
  @override
  /// Sends that failed on the way out, waiting to be retried.
  ///
  /// On the class because two mixins need it: the send mixin holds and takes,
  /// the history mixin restores and drops (CODE_STYLE §5). Not persisted — it
  /// lives as long as the app is open, which is the whole of what Rift keeps
  /// locally.
  @override
  final Outbox _outbox = Outbox();

  /// See [KeySweepDoorbell]. One per selected server, not per channel.
  @override
  final KeySweepDoorbell _sweepDoorbell = KeySweepDoorbell();

  @override
  late final ChannelKeyring _keyring = ChannelKeyring(
    serverCubit: _serverCubit,
    vaultCubit: _vaultCubit,
    crypto: _crypto,
    onHealed: _ringKeySweepDoorbell,
  );

  /// Unwrapped channel keys for the open channel, by key version.
  @override
  Map<int, Uint8List> get _keys => _keyring.keys;

  /// The open channel's newest key version (0 = none yet).
  @override
  int get _currentKeyVersion => _keyring.currentVersion;

  @override
  Future<ChatIdentity?> _chatIdentity(Server server) =>
      _keyring.chatIdentity(server);

  /// Guards against a stale async continuation writing into a newer channel.
  /// How long to let a keyring heal happen before calling it a wait.
  ///
  /// Long enough for the round trip the doorbell starts — ring, another
  /// member's client wraps the key, our retry picks it up — and short enough
  /// that somebody genuinely without access is not left watching a spinner
  /// wondering whether anything is happening.
  @visibleForTesting
  static const keyHealGrace = Duration(seconds: 3);

  int _openGeneration = 0;

  /// How much the open channel may interrupt, asked of whoever keeps that.
  ///
  /// [ServerNotificationsCubit] holds every server's levels and sets this on
  /// construction. Null before it has, and until then the default answers —
  /// which is the right way round: a chat that started before the levels
  /// arrived should behave like an unconfigured one, not a silent one.
  @override
  NotificationLevel Function(String channelId)? _notificationLevelFor;

  /// Called by [ServerNotificationsCubit]. See [_notificationLevelFor].
  void setNotificationLevelSource(
    NotificationLevel Function(String channelId) source,
  ) => _notificationLevelFor = source;

  StreamSubscription<VaultState>? _vaultSub;

  ChannelChatCubit({
    required ServerCubit serverCubit,
    required VaultCubit vaultCubit,
    CryptoRepository? crypto,
  }) : _serverCubit = serverCubit,
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

    _resetTo(
      ChannelChatState(status: ChannelChatStatus.loading, channelId: channelId),
    );

    final server = _serverCubit.state.selectedServer;
    _openServerId = server?.id;
    if (server == null || server.user == null) {
      emit(
        state.copyWith(
          status: ChannelChatStatus.error,
          failure: const ChatFailure.noServer(),
        ),
      );
      return;
    }

    await _keyring.ensureChatKeyPublished(server);
    if (_isStale(generation)) return;

    final keyring = await _keyring.loadOrBootstrap(channelId);
    if (_isStale(generation)) return;

    if (keyring.failure != null) {
      emit(
        state.copyWith(
          status: ChannelChatStatus.error,
          failure: keyring.failure ?? const ChatFailure.unknown(),
        ),
      );
      return;
    }

    _setupRealtime(server, channelId);

    // Who is listening, before the messages. A member is entitled to know a
    // bot holds this channel's key *while reading it*, not a moment after.
    final listeners = await _serverCubit.channelListeners(channelId);
    if (_isStale(generation)) return;
    emit(state.copyWith(botListeners: listeners));

    // And which bots a `/` command here can reach, before there is a composer
    // to type one into. Asked with the channel, so a private one answers with
    // the bots seated in it rather than with the server's.
    final bots = await _serverCubit.listBots(channelId: channelId);
    if (_isStale(generation)) return;
    emit(state.copyWith(bots: bots));

    // The history is fetched either way, including when no key was found.
    // Without a key most of it comes back as locked rows and any webhook
    // message comes back readable — which is the difference between a channel
    // that looks empty and one that looks like what it is.
    await _fetchLatest(channelId);
    if (_isStale(generation)) return;

    if (keyring.isWaiting) {
      // No entry sealed to us yet — another member's client will heal us.
      // Ring the sweep doorbell so online members re-check right away, even
      // if the original "newly published" ring was lost.
      _ringKeySweepDoorbell();

      // Hold a loading state through the heal window, whatever came back.
      //
      // Almost always this is somebody opening a channel for the first time,
      // and the doorbell just rung is answered in well under a second. Drawing
      // the honest answer for that moment — a wall of "you do not have the key
      // for this yet" over rows that are about to decrypt — tells a new member
      // they are locked out of a room they are already in, and then takes it
      // back. Locked rows are worth showing for a wait; they are not worth
      // showing for a round trip.
      emit(state.copyWith(status: ChannelChatStatus.healingKey));
      await Future.delayed(keyHealGrace);

      // A heal that landed reopened the channel, which bumps the generation
      // and makes this emit stale — so anything below is only ever reached by
      // a wait that really did go unanswered.
      if (_isStale(generation)) return;

      // Now it is a wait rather than a round trip, so say so: locked rows and
      // any readable webhook message if there are any, and the panel that
      // explains why if the channel came back empty.
      emit(
        state.copyWith(
          status: state.messages.isEmpty
              ? ChannelChatStatus.waitingForKey
              : ChannelChatStatus.readOnly,
        ),
      );
      return;
    }

    emit(state.copyWith(status: ChannelChatStatus.ready));
  }

  /// Emit a fresh chat state, dropping the caches that only described the old
  /// one.
  ///
  /// The mention cache describes the channel that was open, so it goes with
  /// it — see [MentionNameCache] for what leaving half of it behind cost.
  void _resetTo(ChannelChatState next) {
    _mentionCache.reset();
    emit(next);
  }

  Future<void> closeChannel() async {
    _openGeneration++;
    _openServerId = null;
    await _teardownRealtime();
    _keyring.clear();
    if (!isClosed) _resetTo(const ChannelChatState());
  }

  /// Retry entry point for the waiting/error states (UI button + doorbell).
  @override
  Future<void> retry() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    _resetTo(const ChannelChatState());
    await openChannel(channelId);
  }

  bool _isStale(int generation) => isClosed || generation != _openGeneration;

  /// The server the open channel belongs to.
  ///
  /// Not `_rtServerId`, which this used to compare against: that is realtime
  /// bookkeeping, and it is null for the whole of [openChannel] between the
  /// teardown at the top and the subscribe at the bottom — two network round
  /// trips later. Any `ServerCubit` emission in that window read as "the
  /// server changed" and closed the channel that was still opening, so the
  /// click did nothing and nothing was logged. Rare until something started
  /// refreshing server details more often, and then it was every time.
  String? _openServerId;

  void _onServerChanged(ServerState serverState) {
    // Switching (or losing) the server closes the open chat.
    final serverId = serverState.selectedServer?.id;
    if (state.channelId != null &&
        _openServerId != null &&
        serverId != _openServerId) {
      closeChannel();
    }
    _ensureServerChatReady();
  }

  @override
  void _ringKeySweepDoorbell() {
    try {
      _sweepDoorbell.ring();
    } catch (_) {}
  }

  // ──────────────────────────────────────────────────────────
  // Doorbell senders
  // ──────────────────────────────────────────────────────────
  // Implemented here rather than in the realtime mixin because the mixins that
  // ring them declare them abstractly; the topic they write to is the mixin's.

  @override
  void _onFreshIncoming(List<ChatMessage> incoming) {
    for (final m in incoming) {
      _removeTyping(m.authorId);
    }
    // A locked row has no text, so a notification for one would be an empty
    // quote under somebody's name. Being unable to read it is exactly the
    // reason not to speak for it.
    _notify(incoming.where((m) => !m.isLocked).toList());
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

  /// Notify other members that one message was edited or deleted.
  ///
  /// Deliberately does not say *which* of the two, or carry the new text: the
  /// receiver re-reads the row and finds out, so a forged broadcast costs a
  /// request instead of putting words in someone's mouth or hiding a message.
  @override
  void _ringChangeDoorbell(String messageId) {
    try {
      _rtChannel?.sendBroadcastMessage(
        event: 'message_changed',
        payload: {'message_id': messageId},
      );
    } catch (_) {}
  }

  /// Notify other members that one message's reactions changed, so they
  /// re-fetch that message. Same fire-and-forget pattern as [_ringDoorbell].
  ///
  /// The id is what keeps the other side's response proportional: without it
  /// every listener re-reads reactions for its whole loaded history.
  @override
  void _ringReactionDoorbell(String messageId) {
    try {
      _rtChannel?.sendBroadcastMessage(
        event: 'reaction',
        payload: {'message_id': messageId},
      );
    } catch (_) {}
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

  /// Re-read who holds this channel's key.
  ///
  /// The header chip is the standing marker BOTS.md §6 rule 4 asks for, and a
  /// marker that is only correct at the moment a channel was opened is not a
  /// standing one. Granting or revoking from the dialog calls this, so the
  /// header stops saying a bot is reading a room it was just shut out of.
  Future<void> refreshBotListeners() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    final listeners = await _serverCubit.channelListeners(channelId);
    if (isClosed || state.channelId != channelId) return;
    emit(state.copyWith(botListeners: listeners));
  }
}
