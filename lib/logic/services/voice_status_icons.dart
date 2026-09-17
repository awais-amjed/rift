import '../../data/classes/participant_info.dart';

/// What a roster row says somebody is doing.
enum VoiceStatusIcon {
  /// They have a screen or window shared.
  sharingScreen,

  /// They have an application's sound shared.
  sharingSound,

  /// They have deafened themselves.
  deafened,

  /// A moderator has deafened them.
  deafenedByModerator,

  /// Their microphone is off — their own choice, or because they are deafened,
  /// which takes the microphone with it.
  muted,

  /// A moderator is holding their microphone.
  mutedByModerator,

  /// *You* have muted them, for yourself only.
  mutedForYou,

  /// Nothing is wrong and they can be heard.
  micOn,
}

/// The icons for one row, left to right.
///
/// Deafening always carries a muted microphone: you cannot hold up your end of
/// a conversation you cannot hear, so the two are drawn together rather than
/// the headphones alone — which would otherwise read as "can't hear you, but
/// go ahead and talk to them".
///
/// At most one of each kind: whose doing it is (a moderator's or their own)
/// picks *which* icon, never how many.
List<VoiceStatusIcon> voiceStatusIcons(
  ParticipantInfo participant, {

  /// Whether this listener has muted them locally, which is nobody's business
  /// but this client's and so is not in [participant].
  required bool mutedForYou,
}) {
  final icons = <VoiceStatusIcon>[];
  if (participant.isSharingScreen) icons.add(VoiceStatusIcon.sharingScreen);
  if (participant.isSharingSound) icons.add(VoiceStatusIcon.sharingSound);

  final deafened = participant.isServerDeafened || participant.isDeafened;
  if (participant.isServerDeafened) {
    icons.add(VoiceStatusIcon.deafenedByModerator);
  } else if (participant.isDeafened) {
    icons.add(VoiceStatusIcon.deafened);
  }

  if (mutedForYou) {
    icons.add(VoiceStatusIcon.mutedForYou);
  } else if (participant.isServerMuted) {
    icons.add(VoiceStatusIcon.mutedByModerator);
  } else if (deafened || !participant.isMicrophoneEnabled) {
    icons.add(VoiceStatusIcon.muted);
  } else {
    icons.add(VoiceStatusIcon.micOn);
  }
  return icons;
}
