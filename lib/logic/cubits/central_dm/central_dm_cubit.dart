import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, RealtimeChannel;

import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/friend_directory.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/repositories/central_dm_repository.dart';
import 'package:rift_crypto/rift_crypto.dart';
import '../../../supabase_config.dart';
import '../../../data/enums/home_surface.dart';
import '../../../data/enums/friendship_state.dart';
import '../../../data/enums/notification_level.dart';
import '../../helper_methods.dart';
import '../../services/central_handle.dart';
import '../../services/push_service.dart';
import '../../services/attachment_cache.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_message_ops.dart';
import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../app/app_cubit.dart';
import '../vault/vault_cubit.dart';

part 'central_dm_state.dart';
part 'central_dm_ready.dart';
part 'central_dm_conversations.dart';
part 'central_dm_friends.dart';
part 'central_dm_unread.dart';
part 'central_dm_decrypt.dart';
part 'central_dm_history.dart';
part 'central_dm_send.dart';
part 'central_dm_edit.dart';

/// Central DMs — the discovery/first-contact tier (ARCHITECTURE.md §4).
///
/// Same Design-1 crypto as server DMs, but identities are derived for the
/// central host, people are found by handle in a public directory, and the
/// central server enforces the funnel limits (daily quota, 30-day TTL,
/// history cap). Requires a signed-in central account and an unlocked vault;
/// privacy-mode users simply see the signed-out state.
class CentralDmCubit extends Cubit<CentralDmState>
    with
        _CentralDmDecryptMixin,
        _CentralDmConversationsMixin,
        _CentralDmFriendsMixin,
        _CentralDmHistoryMixin,
        _CentralDmSendMixin,
        _CentralDmEditMixin,
        _CentralDmUnreadMixin,
        // Last, because it is `on` the unread mixin: readiness is the thing
        // that puts all the others to work, so everything it calls has to be
        // in place before it is applied.
        _CentralDmReadyMixin {
  @override
  final CentralDmRepository _repo;
  @override
  final VaultCubit _vaultCubit;
  @override
  final AppCubit _appCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<VaultState>? _vaultSub;
  StreamSubscription<AppState>? _appSub;
  @override
  RealtimeChannel? _incoming;

  /// The last surface seen, so an [AppState] change that isn't a navigation
  /// doesn't re-run the read sweep.
  HomeSurface _lastSurface;

  @override
  final Map<String, Uint8List> _dmKeys = {};

  /// Signing keys per peer from the directory (base64) — for verification.
  @override
  final Map<String, String> _peerSigningKeys = {};

  /// Chat keys per peer from the directory (base64) — for DM derivation.
  @override
  final Map<String, String> _peerChatKeys = {};

  /// Diffs conversation snapshots to raise notifications for new central DMs.
  final NewMessageNotifier _notifier = NewMessageNotifier();

  CentralDmCubit({
    required VaultCubit vaultCubit,
    required AppCubit appCubit,
    CentralDmRepository? repo,
    CryptoRepository? crypto,
  }) : _vaultCubit = vaultCubit,
       _appCubit = appCubit,
       _lastSurface = appCubit.state.surface,
       _repo = repo ?? CentralDmRepository(),
       _crypto = crypto ?? CryptoRepository(),
       super(const CentralDmState()) {
    _authSub = _repo.authChanges.listen((_) => _ensureReady());
    _vaultSub = vaultCubit.stream.listen((_) => _ensureReady());
    _appSub = appCubit.stream.listen(_onAppStateChanged);
    WindowFocusService.instance.focused.addListener(_onFocusChanged);
    _ensureReady();
  }

  /// Arriving at Home, or coming back to the window, reads whatever
  /// conversation is open there.
  void _onAppStateChanged(AppState appState) {
    if (appState.surface == _lastSurface) return;
    _lastSurface = appState.surface;
    markOpenConversationRead();
  }

  void _onFocusChanged() => markOpenConversationRead();

  @override
  String? get _myUserId => _repo.currentUser?.id;

  /// A friendship or a block changed — on this device or another one.
  ///
  /// Both lists are re-read, because most changes here move a row between
  /// them and two of them (declining, and the peer deleting their request)
  /// remove messages.
  @override
  void _onGraphChanged() {
    if (isClosed) return;
    unawaited(loadFriends().then((_) => refreshConversations()));
  }

  @override
  void _onIncoming() {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(_fetchAfterLatest());
    }
  }

  /// The peer edited a message. `_fetchAfterLatest` can't see it — an edited
  /// message is not a newer one — so the row is re-read by id.
  @override
  void _onMessageUpdated(String messageId) {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(refreshMessage(messageId));
    }
  }

  @override
  Future<void> _teardown() async {
    final channel = _incoming;
    _incoming = null;
    _dmKeys.clear();
    _notifier.reset();
    // Cursors belong to the signed-in account, not the app.
    _resetUnread();
    // Decrypted attachment bytes are held outside any cubit's state, so an
    // account going away has to empty them too. Self-hosted entries go with
    // them — the cache isn't keyed by tier, and all of it is re-downloadable.
    //
    // Only when there was a session to end. This runs on every vault emission
    // for anyone with no central account at all, and throwing away a
    // privacy-mode user's cached images on each one would be a steady trickle
    // of re-downloads for nothing.
    if (channel != null) AttachmentCache.instance.clear();
    if (channel != null) await _repo.unsubscribe(channel);
  }

  /// Blocked peers are left out, and nobody else needs to be: since the gate
  /// went in nothing can arrive from somebody who is not a friend, so there is
  /// no stranger left to filter. What can still arrive is an old message from
  /// somebody blocked afterwards, and they should not get to ring a phone with
  /// it.
  @override
  void _notifyFromConversations(List<DmConversation> conversations) {
    _notifier.scan(
      state.graph.visible(conversations),
      titleFor: (c) => c.peerName,
    );
  }

  /// Seeds the add-friend field and shows the page it lives on — see
  /// [CentralDmState.handleQuery]. The field clears it once consumed, so
  /// arriving twice from the same member re-seeds rather than being swallowed
  /// as a no-op.
  void setHandleQuery(String? query) {
    final trimmed = query?.trim();
    final empty = trimmed?.isEmpty ?? true;
    emit(
      state.copyWith(
        // Opening friends is what makes the seed reachable at all: the field
        // is on that page, and on a phone the pane it would land in is
        // showing the conversation list until something says otherwise.
        closeConversation: !empty,
        friendsOpen: !empty,
        handleQuery: empty ? null : trimmed,
        clearHandleQuery: empty,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // Crypto helpers
  // ──────────────────────────────────────────────────────────

  @override
  Future<Uint8List?> _dmKeyFor(String peerId, String? peerChatKey) async {
    final cached = _dmKeys[peerId];
    if (cached != null) return cached;
    if (peerChatKey == null || _vaultCubit.state.masterSeed == null) {
      return null;
    }
    final identity = await _vaultCubit.getChatIdentityForHost(_centralHost);
    final key = await _crypto.deriveDmKey(
      myKeyPair: identity.keyPair,
      theirPublicKey: CryptoRepository.fromBase64(peerChatKey),
    );
    _dmKeys[peerId] = key;
    return key;
  }

  @override
  Future<ServerIdentity> _signingIdentity() =>
      _vaultCubit.getIdentityForHost(_centralHost);

  // ──────────────────────────────────────────────────────────
  // Lifecycle
  // ──────────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    PushService.instance.token.removeListener(_onPushToken);
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    await _authSub?.cancel();
    await _vaultSub?.cancel();
    await _appSub?.cancel();
    await _teardown();
    return super.close();
  }
}
