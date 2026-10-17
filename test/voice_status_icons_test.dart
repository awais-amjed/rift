import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/logic/services/voice_status_icons.dart';

ParticipantInfo person({
  bool micOn = true,
  bool deafened = false,
  bool serverMuted = false,
  bool serverDeafened = false,
  bool screen = false,
  bool sound = false,
  bool pttIdle = false,
}) => ParticipantInfo(
  identity: 'alice~dev1',
  userId: 'alice',
  name: 'Alice',
  isMicrophoneEnabled: micOn,
  isDeafened: deafened,
  isServerMuted: serverMuted,
  isServerDeafened: serverDeafened,
  isSharingScreen: screen,
  isSharingSound: sound,
  isPushToTalkIdle: pttIdle,
);

List<VoiceStatusIcon> icons(
  ParticipantInfo participant, {
  bool mutedForYou = false,
  bool cannotHear = false,
  bool hiddenFromThem = false,
}) => voiceStatusIcons(
  participant,
  mutedForYou: mutedForYou,
  cannotHear: cannotHear,
  hiddenFromThem: hiddenFromThem,
);

void main() {
  // A bot summoned to play hears nothing without a grant of its own. It is
  // there to be heard, so the ears go and the microphone stays.
  test('a bot that cannot hear shows the ears and not the microphone', () {
    expect(icons(person(), cannotHear: true), [VoiceStatusIcon.cannotHear]);
  });

  test('a deafen says it in its own words, not as a bot that cannot hear', () {
    expect(icons(person(deafened: true), cannotHear: true), [
      VoiceStatusIcon.deafened,
      VoiceStatusIcon.muted,
    ]);
  });

  test('somebody who can be heard shows nothing', () {
    expect(icons(person()), isEmpty);
  });

  test('a muted microphone is shown as one', () {
    expect(icons(person(micOn: false)), [VoiceStatusIcon.muted]);
  });

  // Not talking is not a mute: grey, not the red of somebody refusing.
  test('a push-to-talk key that is up is not drawn as a mute', () {
    expect(icons(person(micOn: false, pttIdle: true)), [
      VoiceStatusIcon.waitingToTalk,
    ]);
  });

  // An attribute arriving late must not soften a deafen or a moderator.
  test('deafening and moderation outrank a waiting push-to-talk key', () {
    expect(icons(person(micOn: false, pttIdle: true, deafened: true)), [
      VoiceStatusIcon.deafened,
      VoiceStatusIcon.muted,
    ]);
    expect(icons(person(micOn: false, pttIdle: true, serverMuted: true)), [
      VoiceStatusIcon.mutedByModerator,
    ]);
  });

  // The headphones alone would read as "can't hear you, but go ahead" —
  // deafening takes the microphone too, and the row has to say both.
  test('deafening shows the ears *and* the microphone', () {
    expect(icons(person(deafened: true, micOn: false)), [
      VoiceStatusIcon.deafened,
      VoiceStatusIcon.muted,
    ]);
  });

  // The mic track survives a moment longer than the deafen does, and a row
  // that believed it would claim somebody deafened can still be heard.
  test('a deafened microphone counts as muted even before its track goes', () {
    expect(icons(person(deafened: true)), [
      VoiceStatusIcon.deafened,
      VoiceStatusIcon.muted,
    ]);
  });

  test('a moderator holding them is a different icon, not another one', () {
    expect(icons(person(serverMuted: true, micOn: false)), [
      VoiceStatusIcon.mutedByModerator,
    ]);
    expect(icons(person(serverDeafened: true, micOn: false)), [
      VoiceStatusIcon.deafenedByModerator,
      VoiceStatusIcon.muted,
    ]);
  });

  // You turning somebody off is about you, and says so differently: they are
  // talking, you are not listening.
  test('muting somebody yourself replaces the microphone icon', () {
    expect(icons(person(), mutedForYou: true), [VoiceStatusIcon.mutedForYou]);
  });

  // Hiding your voice is about what they hear, so it sits beside what they
  // are doing rather than replacing any of it.
  test('hiding your voice from them adds its own icon, last', () {
    expect(icons(person(), hiddenFromThem: true), [
      VoiceStatusIcon.hiddenFromThem,
    ]);
    expect(
      icons(person(micOn: false), mutedForYou: true, hiddenFromThem: true),
      [VoiceStatusIcon.mutedForYou, VoiceStatusIcon.hiddenFromThem],
    );
  });

  test('sharing is shown alongside whatever else is true', () {
    expect(icons(person(screen: true, sound: true)), [
      VoiceStatusIcon.sharingScreen,
      VoiceStatusIcon.sharingSound,
    ]);
    expect(icons(person(screen: true, micOn: false)), [
      VoiceStatusIcon.sharingScreen,
      VoiceStatusIcon.muted,
    ]);
  });
}
