part of 'livekit_cubit.dart';

/// Joining a call between two members (`dm_calls`), and the second
/// connections a share opens into whichever kind of call this is.
///
/// The room is the same kind of room: the same controls, tiles, devices and
/// frame encryption. Three things differ, and they are all here — the token
/// comes from `get_dm_call_token` for a named server rather than from the
/// channel's, the key is handed in already derived rather than loaded from a
/// keyring, and there is no channel for the rest of the app to select.
///
/// Whether the call is *happening* — ringing, answered, hung up — is not this
/// cubit's to know. `DmCallCubit` follows the row and tells this one when to
/// join and when to leave.
mixin _DmCallConnectMixin on Cubit<LiveKitState>, _E2EEMixin {
  AppCubit get _appCubit;
  VoiceApi? get _voiceApi;

  /// Implemented by the other parts.
  Future<void> _cleanupRoom();
  void forgetChannelToken(String? channelId);
  Future<bool> _joinRoom({
    required String livekitUrl,
    required String livekitToken,
    required E2EEOptions e2ee,
    required bool? micEnabled,
    required bool? cameraEnabled,
    required bool tokenWasCached,
    required String callName,
    required String? serverName,
  });

  /// The DM call's media key, kept for as long as the call so a dropped
  /// connection can rejoin without asking the call cubit for it again.
  Uint8List? _dmMediaKey;

  /// Join [place]'s room on [server], encrypted with [mediaKey].
  ///
  /// Leaves whatever call this device was in first, the way picking another
  /// channel does. The selected channel is cleared *after* this call is the
  /// one in the state, which is what tells `VoiceConnectionListener` that
  /// the clearing is a switch rather than a leave.
  Future<void> connectToDmCall({
    required Server server,
    required DmCallPlace place,
    required Uint8List mediaKey,
    bool? micEnabled,
    bool? cameraEnabled,
  }) async {
    final hadRoom = state.room != null;
    final wasConnecting =
        state.connectionState == LiveKitConnectionState.connecting;
    final leaving = state.currentChannelId;

    emit(
      state.copyWith(
        connectionState: LiveKitConnectionState.connecting,
        dmCall: place,
        clearChannelId: true,
        clearFailure: true,
      ),
    );
    _appCubit.setSelectedChannelId(null);

    if (hadRoom || wasConnecting) await _cleanupRoom();
    forgetChannelToken(leaving);
    _clearE2EE();
    _keyring?.clear();
    emit(state.copyWith(clearRoom: true));
    _dmMediaKey = mediaKey;

    final response = await _voiceApi!.getDmCallToken(server, place.callId);
    // Hung up, or replaced by another call, while the token was on its way.
    if (state.dmCall != place) return;
    if (!response.success) {
      HelperMethods.printDebug(
        '[LiveKit] no token for DM call ${place.callId}: ${response.error}',
      );
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: ConnectionFailure.tokenRequest(response.error),
        ),
      );
      return;
    }

    final data = response.data as Map<String, dynamic>;
    final livekitUrl = data['livekit_url'] as String? ?? server.livekitUrl;
    if (livekitUrl == null) {
      emit(
        state.copyWith(
          connectionState: LiveKitConnectionState.error,
          failure: const ConnectionFailure.noLiveKitUrl(),
        ),
      );
      return;
    }

    await _joinRoom(
      livekitUrl: livekitUrl,
      livekitToken: data['token'] as String,
      e2ee: await _prepareFixedKey(mediaKey),
      micEnabled: micEnabled,
      cameraEnabled: cameraEnabled,
      tokenWasCached: false,
      callName: place.peerName,
      serverName: server.name,
    );
  }

  /// Join the DM call this device is in again — a dropped connection, or
  /// "Try again" after a failed join. Nothing happens if the call has been
  /// left, or its server is no longer on this device.
  ///
  /// Public because the room-event and retry paths live in other parts of
  /// this cubit and reach it through an abstract declaration (CODE_STYLE §5).
  Future<void> rejoinDmCall() async {
    final place = state.dmCall;
    final key = _dmMediaKey;
    if (place == null || key == null) return;
    final server = _serverCubit?.state.servers
        .where((s) => s.id == place.serverId)
        .firstOrNull;
    if (server == null) return;
    await connectToDmCall(server: server, place: place, mediaKey: key);
  }

  /// A token for a second connection into the call this device is in — a
  /// screen share or a sound share — from whichever mint the call came from.
  Future<APIResponse> shareToken({
    bool screenShare = false,
    bool soundShare = false,
  }) async {
    final voice = _voiceApi;
    final session = _session;
    if (voice == null || session == null) {
      return APIResponse.error('No server');
    }
    final place = state.dmCall;
    if (place != null) {
      final server = session.serverById(place.serverId);
      if (server == null) return APIResponse.error('No server');
      return voice.getDmCallToken(
        server,
        place.callId,
        screenShare: screenShare,
        soundShare: soundShare,
      );
    }
    final channelId = state.currentChannelId;
    if (channelId == null) return APIResponse.error('Not in a call');
    return voice.getChannelToken(
      channelId,
      screenShare: screenShare,
      soundShare: soundShare,
    );
  }
}
