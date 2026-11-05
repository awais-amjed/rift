import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Patch 10 of the vendored livekit_client: starting a remote track turns it
/// on, which for a share's held sound played a moment of it on every join.
class _Native extends Fake implements rtc.MediaStreamTrack {
  bool on = false;
  @override
  String? get id => 'TR_test';
  @override
  String? get kind => 'audio';
  @override
  set enabled(bool value) => on = value;
  @override
  bool get enabled => on;
  @override
  Future<void> stop() async {}
}

class _Stream extends Fake implements rtc.MediaStream {
  @override
  String get id => 'PA_test|TR_test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<bool> onAfterStart({required bool held}) async {
    final native = _Native();
    final track = RemoteAudioTrack(
      TrackSource.screenShareAudio,
      _Stream(),
      native,
    )..holdOnStart = held;
    await track.start();
    final on = native.on;
    await track.stop();
    return on;
  }

  test('a held track stays off when it starts', () async {
    expect(await onAfterStart(held: true), isFalse);
  });

  test('any other track is turned on when it starts', () async {
    expect(await onAfterStart(held: false), isTrue);
  });
}
