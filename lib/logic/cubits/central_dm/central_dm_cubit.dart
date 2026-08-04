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
import '../../helper_methods.dart';
import '../../services/chat_attachment_uploader.dart';
import '../../services/chat_message_ops.dart';
import '../../services/notification_service.dart';
import '../vault/vault_cubit.dart';

part 'central_dm_state.dart';
part 'central_dm_conversations.dart';
part 'central_dm_history.dart';
part 'central_dm_send.dart';
part 'central_dm_edit.dart';
part 'central_dm_reactions.dart';

/// Central DMs — the discovery/first-contact tier (ARCHITECTURE.md §4).
///
/// Same Design-1 crypto as server DMs, but identities are derived for the
/// central host, people are found by handle in a public directory, and the
/// central server enforces the funnel limits (daily quota, 30-day TTL,
/// history cap). Requires a signed-in central account and an unlocked vault;
/// privacy-mode users simply see the signed-out state.
class CentralDmCubit extends Cubit<CentralDmState>
    with
        _CentralDmConversationsMixin,
        _CentralDmHistoryMixin,
        _CentralDmSendMixin,
        _CentralDmEditMixin,
        _CentralDmReactionsMixin {
  @override
  final CentralDmRepository _repo;
  final VaultCubit _vaultCubit;
  @override
  final CryptoRepository _crypto;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<VaultState>? _vaultSub;
  RealtimeChannel? _incoming;

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
    CentralDmRepository? repo,
    CryptoRepository? crypto,
  }) : _vaultCubit = vaultCubit,
       _repo = repo ?? CentralDmRepository(),
       _crypto = crypto ?? CryptoRepository(),
       super(const CentralDmState()) {
    _authSub = _repo.authChanges.listen((_) => _ensureReady());
    _vaultSub = vaultCubit.stream.listen((_) => _ensureReady());
    _ensureReady();
  }

  static String get _centralHost => Uri.parse(SupabaseConfig.supabaseUrl).host;

  @override
  String? get _myUserId => _repo.currentUser?.id;

  // ──────────────────────────────────────────────────────────
  // Readiness: session + vault + directory profile
  // ──────────────────────────────────────────────────────────

  bool _settingUp = false;

  Future<void> _ensureReady() async {
    if (_settingUp || isClosed) return;
    _settingUp = true;
    try {
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
    } finally {
      _settingUp = false;
    }
  }

  /// Claim (or re-claim) a handle and publish the central chat identity.
  Future<void> claimHandle(String handle) async {
    final normalized = handle.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalized)) {
      emit(
        state.copyWith(
          error: 'Handles are 3–20 characters: a–z, 0–9, underscore.',
        ),
      );
      return;
    }
    emit(state.copyWith(claiming: true, clearError: true));

    final chat = await _vaultCubit.getChatIdentityForHost(_centralHost);
    final signing = await _vaultCubit.getIdentityForHost(_centralHost);
    final response = await _repo.upsertProfile(
      handle: normalized,
      chatPublicKey: chat.publicKeyBase64,
      signingPublicKey: signing.publicKeyBase64,
    );
    if (isClosed) return;

    if (!response.success) {
      emit(state.copyWith(claiming: false, error: response.error));
      return;
    }
    emit(state.copyWith(claiming: false));
    await _activateProfile(normalized);
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

    _incoming ??= _repo.subscribeIncoming(_onIncoming);
    emit(state.copyWith(status: CentralDmStatus.ready, myHandle: handle));
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

  Future<void> _teardown() async {
    final channel = _incoming;
    _incoming = null;
    _dmKeys.clear();
    _notifier.reset();
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
        .map(
          (row) => DmConversation(
            peerId: row['user_id'] as String,
            peerName: row['handle'] as String,
            peerChatPublicKey: row['chat_public_key'] as String?,
            peerSigningPublicKey: row['signing_public_key'] as String?,
          ),
        )
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
    await _authSub?.cancel();
    await _vaultSub?.cancel();
    await _teardown();
    return super.close();
  }
}
