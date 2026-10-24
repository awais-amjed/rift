import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_call_place.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';

/// "Mute everyone else for me" and "Hide my voice from others" last
/// for one call. Kept after it, the next call would start with everybody
/// silent, or with nobody hearing you and nothing on screen saying why.
void main() {
  const inCall = LiveKitState(
    currentChannelId: 'general',
    currentServerId: 's1',
    listeningOnlyTo: 'alice',
    voiceOnlyFor: 'bob',
  );

  test('a rejoin of the same call keeps both', () {
    final state = inCall.copyWith(
      connectionState: LiveKitConnectionState.connecting,
      currentChannelId: 'general',
      clearRoom: true,
    );
    expect(state.listeningOnlyTo, 'alice');
    expect(state.voiceOnlyFor, 'bob');
  });

  test('leaving drops both', () {
    final state = inCall.copyWith(
      connectionState: LiveKitConnectionState.disconnected,
      clearChannelId: true,
      clearDmCall: true,
    );
    expect(state.listeningOnlyTo, isNull);
    expect(state.voiceOnlyFor, isNull);
  });

  test('moving to another channel drops both', () {
    final state = inCall.copyWith(currentChannelId: 'music');
    expect(state.listeningOnlyTo, isNull);
    expect(state.voiceOnlyFor, isNull);
  });

  test('a DM call does not inherit them', () {
    final state = inCall.copyWith(
      clearChannelId: true,
      dmCall: const DmCallPlace(
        serverId: 's1',
        callId: 'c1',
        peerId: 'alice',
        peerName: 'Alice',
      ),
    );
    expect(state.listeningOnlyTo, isNull);
    expect(state.voiceOnlyFor, isNull);
  });

  test('each turns off on its own', () {
    final state = inCall.copyWith(clearListeningOnlyTo: true);
    expect(state.listeningOnlyTo, isNull);
    expect(state.voiceOnlyFor, 'bob');
  });
}
