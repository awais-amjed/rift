import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';

/// A member's own mute and deafen toggles are *intent*, and moderation is
/// something laid on top of them. Keeping the two apart is what lets a mute be
/// lifted without guessing: whatever the member last chose is still recorded,
/// so it is simply honoured again.
///
/// They used to be conflated. Deafening rewrote the mic toggle to false and
/// un-deafening rewrote it to true, so muting yourself, deafening, then
/// un-deafening turned your microphone back on by itself.
void main() {
  group('LiveKitState.isMicOn', () {
    test('on when the member wants it and nobody has taken it away', () {
      expect(const LiveKitState(isMicEnabled: true).isMicOn, isTrue);
    });

    test('off when the member muted themselves', () {
      expect(const LiveKitState(isMicEnabled: false).isMicOn, isFalse);
    });

    test('off while deafened, without touching the toggle underneath', () {
      const state = LiveKitState(isMicEnabled: true, isDeafened: true);
      expect(state.isMicOn, isFalse);
      // The intent survives, which is what un-deafening restores.
      expect(state.isMicEnabled, isTrue);
    });

    test('off while server muted, and off while server deafened', () {
      expect(
        const LiveKitState(isMicEnabled: true, isServerMuted: true).isMicOn,
        isFalse,
      );
      // Deafened takes the mic too: you cannot hold up your end of a
      // conversation you cannot hear.
      expect(
        const LiveKitState(isMicEnabled: true, isServerDeafened: true).isMicOn,
        isFalse,
      );
    });
  });

  group('lifting moderation restores what the member chose', () {
    // The reported bug: server mute then server unmute left them silent until
    // they toggled their own mic.
    test('a member who had not muted themselves comes back on', () {
      const muted = LiveKitState(isMicEnabled: true, isServerMuted: true);
      expect(muted.isMicOn, isFalse);

      final released = muted.copyWith(isServerMuted: false);
      expect(released.isMicOn, isTrue);
    });

    test('a member who had muted themselves stays muted', () {
      const muted = LiveKitState(isMicEnabled: false, isServerMuted: true);

      final released = muted.copyWith(isServerMuted: false);
      expect(released.isMicOn, isFalse);
      expect(released.isMicEnabled, isFalse);
    });

    test('lifting a server deafen returns both the mic and the ears', () {
      const both = LiveKitState(isMicEnabled: true, isServerDeafened: true);
      expect(both.isMicOn, isFalse);
      expect(both.isDeafenedEffective, isTrue);

      final released = both.copyWith(isServerDeafened: false);
      expect(released.isMicOn, isTrue);
      expect(released.isDeafenedEffective, isFalse);
    });

    test(
      'a member deafened by choice stays deafened when the server lifts',
      () {
        const both = LiveKitState(isDeafened: true, isServerDeafened: true);

        final released = both.copyWith(isServerDeafened: false);
        expect(released.isDeafenedEffective, isTrue);
        expect(released.isMicOn, isFalse);
      },
    );
  });

  group('LiveKitState.isDeafenedEffective / isModerated', () {
    test('deafened by either their own choice or a moderator', () {
      expect(const LiveKitState().isDeafenedEffective, isFalse);
      expect(const LiveKitState(isDeafened: true).isDeafenedEffective, isTrue);
      expect(
        const LiveKitState(isServerDeafened: true).isDeafenedEffective,
        isTrue,
      );
    });

    test('only a moderator makes the local controls unusable', () {
      // Deafening yourself is not moderation — the button still works.
      expect(const LiveKitState(isDeafened: true).isModerated, isFalse);
      expect(const LiveKitState(isServerMuted: true).isModerated, isTrue);
      expect(const LiveKitState(isServerDeafened: true).isModerated, isTrue);
    });
  });
}
