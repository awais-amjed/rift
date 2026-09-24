part of 'livekit_cubit.dart';

/// Over the cubit-part budget and one job: answering the room's events. It is a
/// list of listeners, each short.
mixin _RoomEventsMixin on Cubit<LiveKitState>, _E2EEMixin {
  List<EventsListener<RoomEvent>> get _listeners;
  Map<String, Set<String>> get _watchingSeen;
  SoundboardCubit? get _soundboardCubit;
  AppCubit get _appCubit;
  TokenCubit get _tokenCubit;
  void _syncParticipants();
  Future<void> _publishSelfState();

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
    _watchingSeen.clear();

    listener
      ..on<ParticipantConnectedEvent>((e) {
        final identity = e.participant.identity;
        // Their key before their audio: a frame cryptor with no key for a
        // participant drops their frames, and somebody who joined a moment
        // before you registered them would simply never be audible.
        unawaited(_registerParticipantKey(identity));
        _seedWatching(e.participant);
        if (ParticipantIdentity.isShare(identity)) {
          SoundService.instance.play(AppSound.stream);
        } else {
          SoundService.instance.play(AppSound.presence);
        }
        _syncParticipants();
        _applyStoredSettings();
      })
      ..on<ParticipantDisconnectedEvent>((e) {
        final identity = e.participant.identity;
        _watchingSeen.remove(identity);
        _forgetStream(identity);
        if (ParticipantIdentity.isShare(identity)) {
          SoundService.instance.play(AppSound.stream, ending: true);
        } else {
          SoundService.instance.play(AppSound.presence, ending: true);
        }
        _syncParticipants();
      })
      ..on<TrackPublishedEvent>((e) {
        _seedWatching(e.participant);
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
        } else if (_isStreamTrack(e.participant, e.publication)) {
          // A phone streams on the connection it talks on, so its stream
          // starting is a track arriving, not somebody joining.
          if (!ParticipantIdentity.isScreenshare(e.participant.identity) &&
              e.publication.source == TrackSource.screenShareVideo) {
            SoundService.instance.play(AppSound.stream);
          }
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
        _seedWatching(e.participant);
        _syncParticipants();
        // Their key, again, and this is the one that actually matters for
        // somebody who was already here when we arrived: `room.connect`
        // resolves before `remoteParticipants` is populated, so the sweep at
        // connect registers nobody, and `ParticipantConnected` only ever fires
        // for people who arrive *after* you. Whoever joined second heard
        // silence — connected, subscribed, and decrypting nothing.
        unawaited(_registerTrackKey(e.participant.identity));
        // Saved mute and volume, now that there is a track to put them on.
        // Publishing is too early: the track arrives after it, so somebody
        // who came back, or streamed again, was heard at full volume.
        _applyStoredSettings();

        if (ParticipantIdentity.isSoundShare(e.participant.identity)) {
          if (_isOwnShare(e.participant.identity)) {
            e.publication.unsubscribe();
          }
        } else if (_isStreamTrack(e.participant, e.publication)) {
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
        }
      })
      ..on<TrackUnpublishedEvent>((e) {
        if (!ParticipantIdentity.isScreenshare(e.participant.identity) &&
            e.publication.source == TrackSource.screenShareVideo) {
          SoundService.instance.play(AppSound.stream, ending: true);
          _forgetStream(e.participant.identity);
        }
        _syncParticipants();
      })
      // Your own phone stream, which on a desktop would arrive as somebody
      // joining: the sharer hears it start and end like everyone else.
      ..on<LocalTrackPublishedEvent>((e) {
        // And your own key, on the cryptor LiveKit has just built for this
        // track. Your microphone is published *inside* `room.connect`, before
        // any key exists to index by — see [_registerTrackKey] for what that
        // costs. Every later publish comes through here too: unmuting, the
        // camera, a rebuilt track after the input device moved.
        unawaited(_registerTrackKey(e.participant.identity));
        if (e.publication.source == TrackSource.screenShareVideo) {
          SoundService.instance.play(AppSound.stream);
        }
      })
      ..on<LocalTrackUnpublishedEvent>((e) {
        if (e.publication.source == TrackSource.screenShareVideo) {
          SoundService.instance.play(AppSound.stream, ending: true);
          _forgetStream(e.participant.identity);
        }
      })
      ..on<ActiveSpeakersChangedEvent>((e) => _syncParticipants())
      ..on<TrackMutedEvent>((e) => _syncParticipants())
      ..on<TrackUnmutedEvent>((e) => _syncParticipants())
      // Server-side moderation state arrives via participant metadata and
      // permission updates (moderate_user edge function).
      ..on<ParticipantMetadataUpdatedEvent>((e) => _syncParticipants())
      // Somebody deafening themselves is published rather than visible —
      // see [VoiceAttributes].
      ..on<ParticipantAttributesChanged>((e) {
        _syncParticipants();
        _cueWatching(e);
      })
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

        // The call itself has moved to another LiveKit. The channel is the
        // one we are already in, so nothing about the sidebar changes — but
        // the cached token names the node we are leaving, so it goes first or
        // the rejoin lands us straight back where we were.
        if (VoiceSignal.isRejoin(
          data: e.data,
          topic: e.topic,
          fromServer: e.participant == null,
        )) {
          final here = state.currentChannelId;
          if (here != null) {
            _tokenCubit.invalidateToken(here);
            unawaited(connectToChannel(channelId: here));
          }
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
    SoundService.instance.play(AppSound.presence);
    _appCubit.setSelectedChannelId(channelId);
  }

  /// Records where [participant] already is, the first time this client
  /// hears of them. Everyone present when this client joins arrives without a
  /// `ParticipantConnected` (see `TrackSubscribedEvent` below), and an
  /// attribute change is only a change against something already known.
  void _seedWatching(Participant participant) {
    if (participant is! RemoteParticipant) return;
    _watchingSeen.putIfAbsent(
      participant.identity,
      () => VoiceAttributes.watchingOf(participant.attributes),
    );
  }

  /// Plays a tone when somebody else starts or stops watching a stream this
  /// client is sharing or watching — see [watchCues].
  void _cueWatching(ParticipantAttributesChanged e) {
    if (e.participant is! RemoteParticipant) return;
    if (!e.attributes.containsKey(VoiceAttributes.watchingKey)) return;
    final identity = e.participant.identity;
    final current = VoiceAttributes.watchingOf(e.participant.attributes);
    final cues = watchCues(
      watcher: identity,
      previous: _watchingSeen[identity],
      current: current,
      localIdentity: state.room?.localParticipant?.identity,
      watchedHere: state.subscribedScreenshares,
      live: _liveStreams(),
    );
    _watchingSeen[identity] = current;
    // One tone however many streams changed at once; the list is almost
    // always a single entry.
    if (cues.contains(WatchCue.started)) {
      SoundService.instance.play(AppSound.watchers);
    } else if (cues.contains(WatchCue.stopped)) {
      SoundService.instance.play(AppSound.watchers, ending: true);
    }
  }

  /// Whether [publication] is part of somebody's stream, and so waits for
  /// them to be watched. A desktop streams on a `_screenshare` connection of
  /// its own; a phone publishes its screen beside its microphone, and was
  /// sent to everyone in the call whether they had asked to watch or not.
  static bool _isStreamTrack(
    Participant participant,
    TrackPublication publication,
  ) =>
      ParticipantIdentity.isScreenshare(participant.identity) ||
      publication.source == TrackSource.screenShareVideo ||
      publication.source == TrackSource.screenShareAudio;

  /// The streams on air in this call, by the identity a watcher records.
  Set<String> _liveStreams() {
    final room = state.room;
    if (room == null) return const {};
    bool streams(Participant p) =>
        ParticipantIdentity.isScreenshare(p.identity) ||
        p.videoTrackPublications.any(
          (pub) => pub.source == TrackSource.screenShareVideo,
        );
    return {
      for (final p in room.remoteParticipants.values)
        if (streams(p)) p.identity,
      if (room.localParticipant case final local? when streams(local))
        local.identity,
    };
  }

  /// Stops counting [identity]'s stream as watched once it has ended. It
  /// stayed in the list, so the next stream from the same phone opened
  /// already watched, and the room was told this client was still watching.
  void _forgetStream(String identity) {
    if (!state.subscribedScreenshares.contains(identity)) return;
    emit(
      state.copyWith(
        subscribedScreenshares: Set<String>.from(state.subscribedScreenshares)
          ..remove(identity),
      ),
    );
    unawaited(_publishSelfState());
  }
}
