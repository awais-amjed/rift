// The vendored SDK's own transport, which is what is patched.
// ignore_for_file: implementation_imports
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';
import 'package:livekit_client/src/core/transport.dart';

/// Records the teardown calls and answers everything else with nothing.
class _RecordingPeerConnection implements rtc.RTCPeerConnection {
  final calls = <String>[];

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> dispose() async => calls.add('dispose');

  @override
  Future<List<rtc.RTCRtpSender>> getSenders() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  // On Windows and Linux a dispose after a close leaves the connection's
  // remote tracks registered, and a volume or mute sent later by track id can
  // land on a dead one (third_party/livekit_client/RIFT_PATCHES.md, patch 2).
  test('a call connection is disposed before it is closed', () async {
    final pc = _RecordingPeerConnection();
    final transport = await Transport.create(
      (configuration, [constraints = const {}]) async => pc,
      connectOptions: const ConnectOptions(),
    );

    await transport.dispose();

    expect(pc.calls, ['dispose', 'close']);
  });
}
