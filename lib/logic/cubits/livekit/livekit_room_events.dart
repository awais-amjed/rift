part of 'livekit_cubit.dart';

mixin _RoomEventsMixin on Cubit<LiveKitState> {
  List<EventsListener<RoomEvent>> get _listeners;
  AppCubit get _appCubit;
  void _syncParticipants();

  void _applyStoredSettings();
  void _applyScreenshareQualitySettings(Participant participant);

  /// Public because the connection mixin wires this up when a room is
  /// created — cubit-internal, not part of the UI-facing API.
  void setupRoomListeners(Room room) {
    final listener = room.createListener();
    _listeners.add(listener);

    listener
      ..on<ParticipantConnectedEvent>((e) {
        final identity = e.participant.identity;
        if (ParticipantIdentity.isScreenshare(identity)) {
          SoundService.instance.playStreamStarted();
        } else {
          SoundService.instance.playJoin();
        }
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final identity = e.participant.identity;
        if (ParticipantIdentity.isScreenshare(identity)) {
          SoundService.instance.playStreamEnded();
        } else {
          SoundService.instance.playLeave();
        }
        _syncParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();

        if (ParticipantIdentity.isScreenshare(e.participant.identity)) {
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

        if (ParticipantIdentity.isScreenshare(e.participant.identity)) {
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
      ..on<ParticipantPermissionsUpdatedEvent>((e) => _syncParticipants())
      // Staff pulling us into another channel, sent by the `move_user` edge
      // function. Everything else on the data channel is somebody else's.
      ..on<DataReceivedEvent>((e) {
        final destination = VoiceSignal.moveDestination(
          data: e.data,
          topic: e.topic,
          // A packet from the LiveKit API has no sender; a member can't fake
          // that, and a member can't move anyone.
          fromServer: e.participant == null,
        );
        if (destination != null) _onMovedTo(destination);
      })
      ..on<RoomDisconnectedEvent>((e) {
        // Only handle unexpected disconnects; intentional disconnects set state beforehand.
        if (state.connectionState == LiveKitConnectionState.connected) {
          _appCubit.setSelectedChannelId(null);
          emit(
            state.copyWith(
              connectionState: LiveKitConnectionState.disconnected,
              clearRoom: true,
              participants: [],
            ),
          );
        }
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
