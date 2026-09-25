part of 'central_dm_cubit.dart';

/// Becoming — and staying — a usable central account.
///
/// Four things have to line up before this tier can draw anything: a signed-in
/// central session, an unlocked vault to derive the chat identity from, a
/// claimed handle, and a live subscription. They arrive in any order and from
/// different places (GoTrue restoring, the vault unlocking, the user typing a
/// handle), so none of them is a step in a sequence — each just asks for
/// another readiness pass, and the pass works out where things stand.
///
/// [claimHandle] lives here rather than beside the directory calls because a
/// handle is not a profile field on this tier: it is the last of the four, and
/// claiming one is what turns `needsHandle` into `ready`.
mixin _CentralDmReadyMixin
    on Cubit<CentralDmState>, _CentralDmUnreadMixin, _CentralDmPinsMixin {
  @override
  CentralDmRepository get _repo;
  VaultCubit get _vaultCubit;

  /// Owned by the hub, which is also what closes it — see `_teardown`.
  RealtimeChannel? get _incoming;
  set _incoming(RealtimeChannel? channel);

  /// The host every central identity is derived for. Chat and signing keys are
  /// per-host by design (ARCHITECTURE §3), and central is just another host.
  String get _centralHost => Uri.parse(SupabaseConfig.supabaseUrl).host;

  /// Implemented by the hub — the Realtime callbacks it owns.
  Future<void> _teardown();
  void _onIncoming(String senderId);
  void _onMessageUpdated(String messageId, String senderId);
  void _onGraphChanged();

  /// Read cursors and notification levels come from the unread mixin, which
  /// this is `on` rather than declaring them abstractly: two private members
  /// of the same name in one library are one member, and re-declaring them
  /// here left the originals looking unreferenced.
  ///
  /// The rest are implemented by the friends, conversations and send mixins. A
  /// ready account loads all of them, and the order matters — see
  /// [_activateProfile].
  ///
  /// `refreshConversations` is not among them: the unread mixin is applied
  /// before this one and declares it, because the notification level now rides
  /// on a conversation row rather than being fetched on its own.
  Future<void> loadFriends();
  Future<void> refreshQuota();

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
      // Sign-up asked for one (016) and left it in the auth metadata, because
      // the row needs keys only this session can derive. Claim it now; if it
      // was taken in the meantime the panel is already up, with the reason.
      final wanted = user.userMetadata?['handle'];
      if (wanted is String && CentralHandle.isValid(wanted)) {
        await claimHandle(wanted);
      }
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

  /// Tell central where to ring this device, and keep telling it.
  ///
  /// The token is not available at a fixed moment — it arrives asynchronously
  /// on first run and FCM can replace it at any time afterwards — so this
  /// registers whatever is there now and subscribes to whatever comes next.
  /// A phone whose rotated token was never re-registered is a phone that has
  /// silently stopped ringing, which is the failure worth designing against.
  Future<void> _registerDevice() async {
    if (!PushService.isSupported) return;
    PushService.instance.token.removeListener(_onPushToken);
    PushService.instance.token.addListener(_onPushToken);
    await _onPushTokenAsync();
  }

  void _onPushToken() => unawaited(_onPushTokenAsync());

  Future<void> _onPushTokenAsync() async {
    final token = PushService.instance.token.value;
    if (token == null || isClosed) return;
    await _repo.registerDevice(token: token, platform: PushService.platform);
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

    unawaited(_registerDevice());
    _incoming ??= _repo.subscribeIncoming(
      _onIncoming,
      onUpdate: _onMessageUpdated,
      onPrefsChanged: () => unawaited(refreshConversations()),
      onGraphChanged: _onGraphChanged,
      onPinChanged: _onPinChanged,
    );
    emit(state.copyWith(status: CentralDmStatus.ready, myHandle: handle));
    // Before the conversations: the graph is what decides whether each of them
    // is a conversation or a request, and loading them the other way round
    // shows every request in the conversation list for one frame.
    await loadFriends();
    unawaited(refreshConversations());
    unawaited(refreshQuota());
  }
}
