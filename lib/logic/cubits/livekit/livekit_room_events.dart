part of 'livekit_cubit.dart';

mixin _RoomEventsMixin on Cubit<LiveKitState> {
  List<EventsListener<RoomEvent>> get _listeners;
  AppCubit get _appCubit;
  void _syncParticipants();
  void _applyStoredSettings();
  void _applyScreenshareQualitySettings(Participant participant);

  void _setupRoomListeners(Room room) {
    final listener = room.createListener();
    _listeners.add(listener);

    listener
      ..on<ParticipantConnectedEvent>((e) {
        final identity = e.participant.identity;
        if (identity.endsWith('_screenshare')) {
          SoundService.instance.playStreamStarted();
        } else {
          SoundService.instance.playJoin();
        }
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final identity = e.participant.identity;
        if (identity.endsWith('_screenshare')) {
          SoundService.instance.playStreamEnded();
        } else {
          SoundService.instance.playLeave();
        }
        _syncParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        _syncParticipants();
        _applyStoredSettings();

        if (e.participant.identity.endsWith('_screenshare')) {
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

        if (e.participant.identity.endsWith('_screenshare')) {
          if (e.publication.source == TrackSource.screenShareVideo) {
            if (state.subscribedScreenshares.contains(e.participant.identity)) {
              e.publication.setVideoQuality(VideoQuality.HIGH);
            } else {
              e.publication.unsubscribe();
            }
          } else if (e.publication.source == TrackSource.screenShareAudio) {
            if (!state.subscribedScreenshares.contains(e.participant.identity)) {
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
}

