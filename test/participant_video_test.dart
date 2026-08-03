import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rift/logic/services/participant_video.dart';

/// A stand-in for a LiveKit publication — the real class needs a live room,
/// and [ParticipantVideo] only ever reads these three fields.
class _FakePub implements TrackPublication {
  @override
  final TrackSource source;
  @override
  final bool muted;
  final bool hasTrack;

  _FakePub({required this.source, this.muted = false, this.hasTrack = true});

  @override
  Track? get track => hasTrack ? _anyTrack : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only identity matters here — the widget decides how to render it.
final Track _anyTrack = _FakeTrack();

class _FakeTrack implements Track {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('ParticipantVideo.activePublication', () {
    test('camera tile takes the unmuted camera track', () {
      final camera = _FakePub(source: TrackSource.camera);
      final pub = ParticipantVideo.activePublication([
        _FakePub(source: TrackSource.screenShareVideo),
        camera,
      ], isScreenshare: false);
      expect(pub, same(camera));
    });

    test('camera tile falls back to the avatar when the camera is muted', () {
      expect(
        ParticipantVideo.activePublication([
          _FakePub(source: TrackSource.camera, muted: true),
        ], isScreenshare: false),
        isNull,
      );
    });

    test('screenshare tile keeps a muted share track', () {
      final share = _FakePub(source: TrackSource.screenShareVideo, muted: true);
      expect(
        ParticipantVideo.activePublication([share], isScreenshare: true),
        same(share),
      );
    });

    test('a publication with no track is skipped', () {
      expect(
        ParticipantVideo.activePublication([
          _FakePub(source: TrackSource.camera, hasTrack: false),
        ], isScreenshare: false),
        isNull,
      );
      expect(
        ParticipantVideo.activePublication([
          _FakePub(source: TrackSource.screenShareVideo, hasTrack: false),
        ], isScreenshare: true),
        isNull,
      );
    });

    test('a camera tile never picks up a screenshare track', () {
      expect(
        ParticipantVideo.activePublication([
          _FakePub(source: TrackSource.screenShareVideo),
        ], isScreenshare: false),
        isNull,
      );
    });
  });
}
