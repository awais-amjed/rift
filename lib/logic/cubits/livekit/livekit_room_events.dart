part of 'livekit_cubit.dart';

mixin _RoomEventsMixin on Cubit<LiveKitState>, _E2EEMixin {
  List<EventsListener<RoomEvent>> get _listeners;
  SoundboardCubit? get _soundboardCubit;
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;
  void _syncParticipants();

  /// Implemented by [_LiveKitConnectionMixin]; a dropped call joins again
  /// through the same path as a click.
  Future<void> connectToChannel({
    required String channelId,
    bool? micEnabled,
    bool? cameraEnabled,
  });

  void _applyStoredSettings();
  void _applyScreenshareQualitySettings(Participant participant);

  /// Whether [identity] is a share this client started — see
  /// [_LiveKitCubit._isOwnShare].
  bool _isOwnShare(String identity);

  /// Public because the connection mixin wires this up when a room is
  /// created — cubit-internal, not part of the UI-facing API.
  void setupRoomListeners(Room room) {
    final listener = room.createListener();
    _listeners.add(listener);

    listener
      ..on<ParticipantConnectedEvent>((e) {
        final identity = e.participant.identity;
        // Their key before their audio: a frame cryptor with no key for a
        // participant drops their frames, and somebody who joined a moment
        // before you registered them would simply never be audible.
        unawaited(_registerParticipantKey(identity));
        if (ParticipantIdentity.isShare(identity)) {
          SoundService.instance.playStreamStarted();
        } else {
          SoundService.instance.playJoin();
        }
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final identity = e.participant.identity;
        if (ParticipantIdentity.isShare(identity)) {
          SoundService.instance.playStreamEnded();
        } else {
          SoundService.instance.playLeave();
        }
        _syncParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();

        if (ParticipantIdentity.isSoundShare(e.participant.identity)) {
          // A shared track is heard like a person: subscribed by default, and
          // turned down or off per listener. The one exception is the sharer,
          // who is already listening to it out of their own speakers — their
          // own share reaches them as any other participant would, so it has
          // to be dropped explicitly or they hear themselves twice over.
          if (_isOwnShare(e.participant.identity) && e.publication.subscribed) {
            e.publication.unsubscribe();
          }
        } else if (ParticipantIdentity.isScreenshare(e.participant.identity)) {
          if (!state.subscribedScreenshares.contains(e.participant.identity)) {
            // Prevent auto-subscription to unsubscribed screenshares.
            if (e.publication.subscribed) e.publication.unsubscribe();
          } else {
            if (e.publication.source == TrackSource.screenShareVideo) {
              _applyScreenshareQualitySettings(e.participant);
            }
          }
        } else {
          _applyScreenshareQualitySettings(e.participant);
        }
      })
      ..on<TrackSubscribedEvent>((e) {
        _syncParticipants();
        // Their key, again, and this is the one that actually matters for
        // somebody who was already here when we arrived: `room.connect`
        // resolves before `remoteParticipants` is populated, so the sweep at
        // connect registers nobody, and `ParticipantConnected` only ever fires
        // for people who arrive *after* you. Whoever joined second heard
        // silence — connected, subscribed, and decrypting nothing.
        unawaited(_registerSubscribedKey(e.participant.identity));
        // Saved mute and volume, now that there is a track to put them on.
        // Publishing is too early: the track arrives after it, so somebody
        // who came back, or streamed again, was heard at full volume.
        _applyStoredSettings();

        if (ParticipantIdentity.isSoundShare(e.participant.identity)) {
          if (_isOwnShare(e.participant.identity)) {
            e.publication.unsubscribe();
          }
        } else if (ParticipantIdentity.isScreenshare(e.participant.identity)) {
          if (e.publication.source == TrackSource.screenShareVideo) {
            if (state.subscribedScreenshares.contains(e.participant.identity)) {
              e.publication.setVideoQuality(VideoQuality.HIGH);
            } else {
              e.publication.unsubscribe();
            }
          } else if (e.publication.source == TrackSource.screenShareAudio) {
            if (!state.subscribedScreenshares.contains(
              e.participant.identity,
            )) {
              e.publication.unsubscribe();
            }
          }
        } else {
          if (e.publication.source == TrackSource.screenShareVideo) {
            e.publication.setVideoQuality(VideoQuality.HIGH);
          }
        }
      })
      ..on<TrackUnpublishedEvent>((e) => _syncParticipants())
      ..on<ActiveSpeakersChangedEvent>((e) => _syncParticipants())
      ..on<TrackMutedEvent>((e) => _syncParticipants())
      ..on<TrackUnmutedEvent>((e) => _syncParticipants())
      // Server-side moderation state arrives via participant metadata and
      // permission updates (moderate_user edge function).
      ..on<ParticipantMetadataUpdatedEvent>((e) => _syncParticipants())
      // Somebody deafening themselves is published rather than visible —
      // see [VoiceAttributes].
      ..on<ParticipantAttributesChanged>((e) => _syncParticipants())
      ..on<ParticipantPermissionsUpdatedEvent>((e) => _syncParticipants())
      // Two things arrive on the data channel, and which one a packet is
      // turns on whether it has a sender.
      ..on<DataReceivedEvent>((e) {
        // Staff pulling us into another channel, sent by the `move_user` edge
        // function. A packet from the LiveKit API has no sender; a member
        // can't fake that, and a member can't move anyone.
        final destination = VoiceSignal.moveDestination(
          data: e.data,
          topic: e.topic,
          fromServer: e.participant == null,
        );
        if (destination != null) {
          _onMovedTo(destination);
          return;
        }

        // Somebody pressing a soundboard clip. Here the sender is the point:
        // it decides whose cooldown applies and whose mute is honoured, so a
        // packet without one is dropped rather than played.
        final soundId = SoundboardPlay.soundId(
          data: e.data,
          topic: e.topic,
          fromParticipant: e.participant != null,
        );
        if (soundId != null) {
          _soundboardCubit?.hear(
            userId: ParticipantIdentity.userIdOf(e.participant!.identity),
            soundId: soundId,
          );
        }
      })
      ..on<RoomDisconnectedEvent>((e) {
        // Only handle unexpected disconnects; intentional disconnects set state beforehand.
        if (state.connectionState != LiveKitConnectionState.connected) return;

        // The connection gave out rather than somebody ending the call, so
        // join the same channel again with a fresh token instead of leaving
        // the user outside it without a word. The token the SDK spent its
        // retries on is the likeliest reason those retries failed.
        final channelId = state.currentChannelId;
        if (channelId != null && VoiceRejoin.rejoinsAfter(e.reason)) {
          _tokenCubit.invalidateToken(channelId);
          unawaited(connectToChannel(channelId: channelId));
          return;
        }

        _appCubit.setSelectedChannelId(null);
        emit(
          state.copyWith(
            connectionState: LiveKitConnectionState.disconnected,
            clearRoom: true,
            participants: [],
          ),
        );
      });
  }

  /// Joins [channelId] because a moderator said so.
  ///
  /// Goes through the selected channel rather than connecting here, so a move
  /// is the same journey as clicking the channel — token, key, connect, and the
  /// sidebar following along. The join sound is the only cue that it wasn't us:
  /// the pane changes underneath you either way, and silence would read as a
  /// glitch.
  void _onMovedTo(String channelId) {
    if (channelId == state.currentChannelId) return;
    SoundService.instance.playJoin();
    _appCubit.setSelectedChannelId(channelId);
  }
}
