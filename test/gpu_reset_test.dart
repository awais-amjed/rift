import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_call_place.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/services/gpu_reset.dart';

void main() {
  group('GpuReset', () {
    test('a start the runner made after a reset says so', () {
      GpuReset.readArguments(['--rift-profile=cara', GpuReset.flag]);
      expect(GpuReset.startedAfterReset, isTrue);
    });

    test('any other start does not', () {
      GpuReset.readArguments(['--minimized']);
      expect(GpuReset.startedAfterReset, isFalse);
    });
  });

  group('the call a restart rejoins', () {
    final now = DateTime.utc(2026, 11, 18, 14);

    test("a channel's call, deafened as it was", () {
      final call = const LiveKitState(
        currentChannelId: 'voice-1',
        isDeafened: true,
      ).toResume(now);
      expect(call, isNotNull);
      expect(call!.channelId, 'voice-1');
      expect(call.deafened, isTrue);
      expect(call.savedAt, now);
    });

    test('no call, nothing to rejoin', () {
      expect(const LiveKitState().toResume(now), isNull);
    });

    test('a direct call is not rejoined', () {
      const state = LiveKitState(
        dmCall: DmCallPlace(
          serverId: 's',
          callId: 'c',
          peerId: 'p',
          peerName: 'Pat',
        ),
      );
      expect(state.inCall, isTrue);
      expect(state.toResume(now), isNull);
    });
  });
}
