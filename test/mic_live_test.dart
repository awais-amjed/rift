import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';

/// The taskbar's mic badge says people can hear you, so it asks the same
/// rule the call does before it sends the mic ([LiveKitState.transmitsMic]).
void main() {
  const connected = LiveKitConnectionState.connected;

  bool live(
    LiveKitState state, {
    bool pushToTalk = false,
    bool hasKey = true,
  }) => state.micLive(pushToTalk: pushToTalk, hasPushToTalkKey: hasKey);

  group('LiveKitState.micLive', () {
    test('an open mic in a connected call is live', () {
      expect(live(const LiveKitState(connectionState: connected)), isTrue);
    });

    test('not outside a connected call', () {
      for (final other in [
        LiveKitConnectionState.disconnected,
        LiveKitConnectionState.connecting,
        LiveKitConnectionState.error,
      ]) {
        expect(
          live(LiveKitState(connectionState: other)),
          isFalse,
          reason: '$other',
        );
      }
    });

    test('not while muted, deafened, testing the mic or moderated', () {
      for (final state in const [
        LiveKitState(connectionState: connected, isMicEnabled: false),
        LiveKitState(connectionState: connected, isDeafened: true),
        LiveKitState(connectionState: connected, isMicTesting: true),
        LiveKitState(connectionState: connected, isServerMuted: true),
        LiveKitState(connectionState: connected, isServerDeafened: true),
        LiveKitState(connectionState: connected, isSpeakDenied: true),
      ]) {
        expect(live(state), isFalse, reason: '$state');
      }
    });

    test('under push-to-talk, only while the key is held', () {
      const held = LiveKitState(
        connectionState: connected,
        isPushToTalkPressed: true,
      );
      const released = LiveKitState(connectionState: connected);
      expect(live(held, pushToTalk: true), isTrue);
      expect(live(released, pushToTalk: true), isFalse);
    });

    test('never under push-to-talk with no key to press', () {
      const held = LiveKitState(
        connectionState: connected,
        isPushToTalkPressed: true,
      );
      expect(live(held, pushToTalk: true, hasKey: false), isFalse);
    });
  });

  group('LiveKitState.capturesMic', () {
    test('push-to-talk keeps the device open between presses', () {
      const released = LiveKitState(connectionState: connected);
      expect(
        released.capturesMic(pushToTalk: true, hasPushToTalkKey: true),
        isTrue,
      );
      expect(
        released.transmitsMic(pushToTalk: true, hasPushToTalkKey: true),
        isFalse,
      );
    });

    test('the connect path can stand in for the toggle', () {
      const muted = LiveKitState(isMicEnabled: false);
      expect(
        muted.capturesMic(
          pushToTalk: false,
          hasPushToTalkKey: false,
          micEnabled: true,
        ),
        isTrue,
      );
    });
  });
}
