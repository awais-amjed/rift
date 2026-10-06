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

  group('the mic test', () {
    // It plays the microphone back, so the call must neither hear it nor talk
    // over it — and stopping it must hand back exactly what was there.
    test('mutes and deafens for its length, toggles untouched', () {
      const testing = LiveKitState(isMicEnabled: true, isMicTesting: true);
      expect(testing.isMicOn, isFalse);
      expect(testing.isDeafenedEffective, isTrue);
      // What the rest of the call is told, so it shows as deafened there.
      expect(testing.isSelfDeafened, isTrue);
      expect(testing.isDeafened, isFalse);

      final stopped = testing.copyWith(isMicTesting: false);
      expect(stopped.isMicOn, isTrue);
      expect(stopped.isDeafenedEffective, isFalse);
    });

    test('a member deafened before the test is still deafened after it', () {
      const testing = LiveKitState(isDeafened: true, isMicTesting: true);
      final stopped = testing.copyWith(isMicTesting: false);
      expect(stopped.isDeafenedEffective, isTrue);
      expect(stopped.isMicOn, isFalse);
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

  group('LiveKitState.moderationNotice', () {
    test('says nothing when nothing is holding the controls', () {
      expect(const LiveKitState().moderationNotice, isNull);
    });

    test('muting or deafening yourself is not worth explaining', () {
      // These buttons work. Explaining them would be explaining the user's
      // own last action back to them.
      expect(const LiveKitState(isDeafened: true).moderationNotice, isNull);
      expect(const LiveKitState(isMicEnabled: false).moderationNotice, isNull);
    });

    test('a server mute names the mute', () {
      final notice = const LiveKitState(isServerMuted: true).moderationNotice;
      expect(notice, contains('muted'));
      expect(notice, contains('moderator'));
    });

    test('a server deafen names the deafen', () {
      final notice = const LiveKitState(
        isServerDeafened: true,
      ).moderationNotice;
      expect(notice, contains('deafened'));
    });

    test('deafened and muted at once reports the deafen', () {
      // Deafen is the stronger of the two and takes the mic with it, so
      // "muted" would answer the smaller half of the question.
      final notice = const LiveKitState(
        isServerMuted: true,
        isServerDeafened: true,
      ).moderationNotice;
      expect(notice, contains('deafened'));
    });

    test('a notice exists for exactly the states that block the buttons', () {
      for (final state in const [
        LiveKitState(),
        LiveKitState(isDeafened: true),
        LiveKitState(isServerMuted: true),
        LiveKitState(isServerDeafened: true),
        LiveKitState(isServerMuted: true, isServerDeafened: true),
      ]) {
        expect(
          state.moderationNotice != null,
          state.isModerated,
          reason: 'notice and isModerated must not drift apart',
        );
      }
    });
  });
}
