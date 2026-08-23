import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthState, RealtimeChannel;

import '../../../data/classes/api_response.dart';
import '../../../data/classes/attachment.dart';
import '../../../data/classes/chat_message.dart';
import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/message_body.dart';
import '../../../data/classes/pending_attachment.dart';
import '../../../data/repositories/central_dm_repository.dart';
import '../../../data/repositories/crypto_repository.dart';
import '../../../supabase_config.dart';
import '../../../data/enums/home_surface.dart';
import '../../helper_methods.dart';
import '../../services/central_handle.dart';
import '../../services/attachment_cache.dart';
import '../../services/attachment_cleanup.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_message_ops.dart';
import '../../services/dm_unread_scan.dart';
import '../../services/notification_service.dart';
import '../../services/window_focus_service.dart';
import '../app/app_cubit.dart';
import '../vault/vault_cubit.dart';

part 'central_dm_state.dart';
part 'central_dm_conversations.dart';
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
        _CentralDmHistoryMixin,
        _CentralDmSendMixin,
        _CentralDmEditMixin,
        _CentralDmUnreadMixin {
  @override
  final CentralDmRepository _repo;
  final VaultCubit _vaultCubit;
  @override
  final AppCubit _appCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<VaultState>? _vaultSub;
  StreamSubscription<AppState>? _appSub;
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

  static String get _centralHost => Uri.parse(SupabaseConfig.supabaseUrl).host;

  @override
  String? get _myUserId => _repo.currentUser?.id;

  // ──────────────────────────────────────────────────────────
  // Readiness: session + vault + directory profile
  // ──────────────────────────────────────────────────────────

  bool _settingUp = false;

  /// A readiness request that arrived while one was already running.
  ///
  /// Dropping it used to lose the session. The constructor runs a pass
  /// immediately, at which point GoTrue has usually not finished restoring —
  /// so that pass correctly decides there is no user and settles on
  /// `signedOut`. The restore then lands *during* it, the guard turned that
  /// event away, and nothing ever asked again: Cloud Backup showed the account
  /// signed in while central DMs showed "sign in to your Rift account", until
  /// some unrelated vault change happened to re-trigger a pass. Whether it
  /// broke came down to which finished first, which is why it only bit
  /// sometimes.
  bool _setupRequested = false;

  /// Runs a readiness pass, and runs another if anything asked while it was
  /// busy. Coalescing rather than queueing: the passes are idempotent, so the
  /// only thing that matters is that the *last* request is honoured.
  Future<void> _ensureReady() async {
    if (isClosed) return;
    if (_settingUp) {
      _setupRequested = true;
      return;
    }
    _settingUp = true;
    try {
      do {
        _setupRequested = false;
        await _readyPass();
      } while (_setupRequested && !isClosed);
    } finally {
      _settingUp = false;
    }
  }

  /// One pass: session, vault, then the directory profile behind them.
  Future<void> _readyPass() async {
    final user = _repo.currentUser;
    if (user == null || _vaultCubit.state.masterSeed == null) {
      await _teardown();
      emit(const CentralDmState(status: CentralDmStatus.signedOut));
      return;
    }
    if (state.status == CentralDmStatus.ready && _incoming != null) return;

    final profileResponse = await _repo.getMyProfile();
    if (isClosed) return;
    if (!profileResponse.success) {
      emit(state.copyWith(status: CentralDmStatus.error));
      return;
    }

    final profile = profileResponse.data as Map<String, dynamic>?;
    if (profile == null) {
      emit(state.copyWith(status: CentralDmStatus.needsHandle));
      return;
    }

    await _activateProfile(profile['handle'] as String);
  }

  /// Drop an error the user has moved on from.
  ///
  /// A refusal describes one attempt, not the field it came from. Left up
  /// while the next handle is being typed it reads as a verdict on what is on
  /// screen now — "already taken" under a handle nobody has yet — and the only
  /// way to clear it was to submit and be refused again.
  void dismissError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
  }

  /// Claim (or re-claim) a handle and publish the central chat identity.
  ///
  /// Reports whether the handle is now ours, so a caller that opened a dialog
  /// knows whether to close it or leave the error on screen.
  Future<bool> claimHandle(String handle) async {
    final normalized = CentralHandle.normalize(handle);
    if (!CentralHandle.isValid(normalized)) {
      emit(state.copyWith(error: CentralHandle.rule));
      return false;
    }
    emit(state.copyWith(claiming: true, clearError: true));

    final chat = await _vaultCubit.getChatIdentityForHost(_centralHost);
    final signing = await _vaultCubit.getIdentityForHost(_centralHost);
    final response = await _repo.upsertProfile(
      handle: normalized,
      chatPublicKey: chat.publicKeyBase64,
      signingPublicKey: signing.publicKeyBase64,
    );
    if (isClosed) return false;

    if (!response.success) {
      emit(state.copyWith(claiming: false, error: response.error));
      return false;
    }
    emit(state.copyWith(claiming: false));
    await _activateProfile(normalized);
    return true;
  }

  Future<void> _activateProfile(String handle) async {
    // Keep the published keys in sync with the seed-derived identity (a
    // restored seed on a new device re-derives the same keys, so this is
    // normally a no-op).
    final chat = await _vaultCubit.getChatIdentityForHost(_centralHost);
    final signing = await _vaultCubit.getIdentityForHost(_centralHost);
    unawaited(
      _repo.upsertProfile(
        handle: handle,
        chatPublicKey: chat.publicKeyBase64,
        signingPublicKey: signing.publicKeyBase64,
      ),
    );

    _incoming ??= _repo.subscribeIncoming(
      _onIncoming,
      onUpdate: _onMessageUpdated,
    );
    emit(state.copyWith(status: CentralDmStatus.ready, myHandle: handle));
    // Cursors first: without them every message reads as unread, so the badge
    // would flash the whole history before settling.
    await _loadReadCursors();
    unawaited(refreshConversations());
    unawaited(refreshQuota());
  }

  void _onIncoming() {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(_fetchAfterLatest());
    }
  }

  /// The peer edited a message. `_fetchAfterLatest` can't see it — an edited
  /// message is not a newer one — so the row is re-read by id.
  void _onMessageUpdated(String messageId) {
    if (isClosed) return;
    unawaited(refreshConversations());
    if (state.chatStatus == DmChatStatus.ready) {
      unawaited(refreshMessage(messageId));
    }
  }

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

  @override
  void _notifyFromConversations(List<DmConversation> conversations) {
    _notifier.scan(conversations, titleFor: (c) => c.peerName);
  }

  // ──────────────────────────────────────────────────────────
  // Directory search
  // ──────────────────────────────────────────────────────────

  /// Seeds the handle-search field — see [CentralDmState.handleQuery]. The
  /// field clears it once consumed, so arriving twice from the same member
  /// re-opens the search rather than being swallowed as a no-op.
  void setHandleQuery(String? query) {
    final trimmed = query?.trim();
    emit(
      state.copyWith(
        handleQuery: trimmed?.isEmpty ?? true ? null : trimmed,
        clearHandleQuery: trimmed?.isEmpty ?? true,
      ),
    );
  }

  Future<List<DmConversation>> searchHandles(String prefix) async {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final response = await _repo.searchHandles(normalized);
    if (!response.success) return const [];
    return ((response.data as List).cast<Map<String, dynamic>>())
        .map(DmConversation.fromDirectoryRow)
        .toList();
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
    WindowFocusService.instance.focused.removeListener(_onFocusChanged);
    await _authSub?.cancel();
    await _vaultSub?.cancel();
    await _appSub?.cancel();
    await _teardown();
    return super.close();
  }
}
