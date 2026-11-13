part of 'livekit_cubit.dart';

mixin _ScreenshareMixin on Cubit<LiveKitState> {
  void _syncParticipants();

  /// Watching is published, so the sharer and the others watching hear it.
  Future<void> _publishSelfState();

  Future<bool> _watchThroughRust(String identity);
  Future<bool> _unwatchThroughRust(String identity);
  void _letGoOfUnwatchedPictures();
  void _syncPictureReception();

  /// Subscribes to a participant's screenshare tracks.
  Future<void> subscribeToScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    // Your own stream from a phone: the picture is already here, so watching
    // it is only a choice to show it, as it is on a desktop, where it comes
    // back as a connection like anyone else's and can be hidden the same way.
    if (identity == room.localParticipant?.identity) {
      _setWatching(identity, true);
      return;
    }

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      HelperMethods.printDebug('[LiveKit] Participant $identity not found');
      return;
    }

    // Watching is recorded before the subscription is asked for, not after.
    // Starting to watch also opens the stream full size, and the tile that
    // opens checks this set as it appears — finding the stream not yet in
    // it, it held what had just been asked for, and the stage showed the
    // sharer's avatar instead of their screen.
    final wasWatching = state.subscribedScreenshares.contains(identity);
    if (!wasWatching) {
      emit(
        state.copyWith(
          subscribedScreenshares: {...state.subscribedScreenshares, identity},
        ),
      );
    }

    var subscribedAny = false;

    for (final pub in participant.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo) {
        // Through the Rust watch connection where it can be, drawn on the
        // GPU; through this room where it cannot ([_RustWatchMixin]).
        if (await _watchThroughRust(identity)) {
          subscribedAny = true;
          continue;
        }
        try {
          // A track the server already sends, held, unless it has not sent
          // one yet; asking again changes nothing.
          await pub.subscribe();
          _syncPictureReception();
          await pub.setVideoQuality(VideoQuality.HIGH);
          HelperMethods.printDebug(
            '[LiveKit] Watching screenshare video from $identity',
          );
          subscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to subscribe to screenshare video: $e',
          );
        }
      }
    }

    // The sound is turned back on by the sync below, now that the stream is
    // in the watched set. It stays subscribed while unwatched, only held
    // ([_AudioReceptionMixin] says why); subscribing is for a track the
    // server never sent.
    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.screenShareAudio) {
        try {
          if (!pub.subscribed) await pub.subscribe();
          HelperMethods.printDebug(
            '[LiveKit] Hearing screenshare audio from $identity',
          );
          subscribedAny = true;
        } catch (e) {
          HelperMethods.printDebug(
            '[LiveKit] Failed to subscribe to screenshare audio: $e',
          );
        }
      }
    }

    if (subscribedAny) {
      _syncParticipants();
      unawaited(_publishSelfState());
    } else {
      HelperMethods.printDebug(
        '[LiveKit] No screenshare tracks found for $identity',
      );
      if (!wasWatching) {
        emit(
          state.copyWith(
            subscribedScreenshares: Set<String>.from(
              state.subscribedScreenshares,
            )..remove(identity),
          ),
        );
      }
    }
  }

  /// Stops watching a participant's stream. Its tracks stay subscribed, held
  /// off by the syncs [_recordUnwatched] runs ([_PicturePauseMixin]).
  Future<void> unsubscribeFromScreenshare(String identity) async {
    final room = state.room;
    if (room == null) return;

    if (identity == room.localParticipant?.identity) {
      _setWatching(identity, false);
      return;
    }

    // Before the participant is looked up: a share that has just gone still
    // has its texture to let go of.
    var unsubscribedAny = await _unwatchThroughRust(identity);

    final participant = room.remoteParticipants[identity];
    if (participant == null) {
      if (unsubscribedAny) _recordUnwatched(identity);
      return;
    }

    if (participant.videoTrackPublications.any(
      (pub) => pub.source == TrackSource.screenShareVideo,
    )) {
      HelperMethods.printDebug(
        '[LiveKit] Holding screenshare video from $identity',
      );
      unsubscribedAny = true;
    }

    // Likewise: the sync below turns it off once the stream has left the
    // watched set ([_AudioReceptionMixin]).
    if (participant.audioTrackPublications.any(
      (pub) => pub.source == TrackSource.screenShareAudio,
    )) {
      HelperMethods.printDebug(
        '[LiveKit] Holding screenshare audio from $identity',
      );
      unsubscribedAny = true;
    }

    if (unsubscribedAny) _recordUnwatched(identity);
  }

  void _recordUnwatched(String identity) {
    final updated = Set<String>.from(state.subscribedScreenshares)
      ..remove(identity);
    emit(state.copyWith(subscribedScreenshares: updated));
    _syncParticipants();
    unawaited(_publishSelfState());
  }

  /// Stops watching every stream — the call bar's Stop watching, which takes
  /// the place of Leave while anything is watched. One press puts them all
  /// away, so the button turns back into Leave rather than staying put for a
  /// second stream the user may not have noticed was still open.
  Future<void> stopWatchingAll() async {
    for (final identity in state.subscribedScreenshares.toList()) {
      await unsubscribeFromScreenshare(identity);
    }
    // A stream whose sharer has just gone has nothing left to unsubscribe
    // from, and would keep the button on Stop watching for nothing.
    if (state.subscribedScreenshares.isNotEmpty) {
      emit(state.copyWith(subscribedScreenshares: const {}));
      _letGoOfUnwatchedPictures();
      _syncParticipants();
      unawaited(_publishSelfState());
    }
  }

  /// Records watching [identity] or not, with nothing to subscribe to.
  void _setWatching(String identity, bool watching) {
    final updated = Set<String>.from(state.subscribedScreenshares);
    if (!(watching ? updated.add(identity) : updated.remove(identity))) return;
    emit(state.copyWith(subscribedScreenshares: updated));
    _syncParticipants();
    unawaited(_publishSelfState());
  }

  /// Toggle screen sharing on/off. [share] is how a browser's or an Android
  /// phone's share goes out; without one the SDK decides. Answers whether it
  /// did: a share cancelled in the browser's picker never started, and the
  /// share button must not say it did.
  Future<bool> toggleScreenShare({
    ScreenShareCaptureOptions? captureOptions,
    SdkShareRequest? share,
  }) async {
    final room = state.room;
    if (room == null) return false;

    final next = !state.isScreenSharing;
    const fallback = ScreenShareCaptureOptions(useiOSBroadcastExtension: false);
    try {
      if (next && share != null) {
        await _publishShare(room.localParticipant!, share);
      } else {
        await room.localParticipant?.setScreenShareEnabled(
          next,
          screenShareCaptureOptions: captureOptions ?? fallback,
        );
      }
      emit(state.copyWith(isScreenSharing: next));
      _syncParticipants();
      return true;
    } catch (e) {
      // Logged rather than stored. This wrote to the state's error field
      // without moving the connection out of `connected`, and the error screen
      // only renders in the error state — so the message was never shown to
      // anyone. Surfacing a failed screen share properly needs its own channel;
      // pretending it is a connection failure would replace a live call with an
      // error page.
      HelperMethods.printDebug('[LiveKit] Screen share failed: $e');
      return false;
    }
  }

  /// [LocalParticipant.setScreenShareEnabled] takes no publish options, and
  /// [RoomOptions.defaultVideoPublishOptions] would move the camera too. The
  /// options stay on the track, so a reconnect publishes it the same way.
  ///
  /// The sound comes only from a browser, and only when the person also chose
  /// it in the browser's picker. A share whose sound cannot go out is ended
  /// whole: it was asked for with sound.
  Future<void> _publishShare(
    LocalParticipant participant,
    SdkShareRequest share,
  ) async {
    final tracks = share.capture.captureScreenAudio
        ? await LocalVideoTrack.createScreenShareTracksWithAudio(share.capture)
        : [await LocalVideoTrack.createScreenShareTrack(share.capture)];
    try {
      for (final track in tracks.whereType<LocalVideoTrack>()) {
        await participant.publishVideoTrack(
          track,
          publishOptions: share.publish,
        );
      }
      for (final track in tracks.whereType<LocalAudioTrack>()) {
        await participant.publishAudioTrack(track, publishOptions: _shareSound);
      }
    } catch (_) {
      await participant.setScreenShareEnabled(false);
      for (final track in tracks) {
        await track.stop();
      }
      rethrow;
    }
  }

  /// A share's sound is music, not a voice: no pauses cut out of it, and
  /// the bitrate Opus needs for music. Mono: the browser's SDK has no way to
  /// publish it in stereo.
  static const _shareSound = AudioPublishOptions(
    dtx: false,
    encoding: AudioEncoding.presetMusicHighQuality,
  );

  /// Whether this phone's share has left the codec it was published in
  /// ([PhoneEncoderWatch]). The publication's own type is no use: a local
  /// track's is empty.
  Future<bool> phoneShareLeftItsCodec() async {
    final track = state.room?.localParticipant
        ?.getTrackPublicationBySource(TrackSource.screenShareVideo)
        ?.track;
    if (track is! LocalVideoTrack) return false;
    final codec = track.codec;
    try {
      final reports = await track.sender?.getStats();
      if (codec == null || reports == null) return false;
      return PhoneEncoderWatch.leftItsCodec(codec, reports);
    } catch (e) {
      HelperMethods.printDebug('[LiveKit] Share stats failed: $e');
      return false;
    }
  }
}
