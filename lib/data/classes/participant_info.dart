import 'dart:convert';

/// A snapshot of one call connection, copied out of the LiveKit room for the
/// sidebar and the tiles. A person with a shared screen or sound is more than
/// one of these; [userId] is what joins them back up.
class ParticipantInfo {
  final String identity;

  /// The user id this participant belongs to, derived from [identity] (which
  /// also carries a device segment). Per-user concerns — local mute/volume,
  /// moderation, de-duplicating a multi-device user — key off this.
  final String userId;

  final String name;
  final bool isSpeaking;
  final bool isMicrophoneEnabled;
  final bool isCameraEnabled;
  final bool isLocal;
  final bool isScreenshare;

  /// Whether this connection is somebody sharing an application's sound. Like
  /// [isScreenshare] it is a second connection of theirs rather than a person,
  /// which is what [isShare] asks.
  final bool isSoundShare;

  /// Whether they have deafened *themselves*. Unlike a muted microphone,
  /// which is visible as an unpublished track, this is a decision inside their
  /// own client — it reaches the room as a participant attribute they publish.
  final bool isDeafened;

  /// Whether they have a screen or a track shared right now. Their share is a
  /// separate connection (or, from a phone, a second track), so this is the
  /// person's row being told what their other connections are doing.
  final bool isSharingScreen;
  final bool isSharingSound;

  /// What a sound share is playing: the name the sharer's client published its
  /// track under, which is the application it was taken from. Empty when the
  /// application named itself nothing, and for anything that is not a share.
  final String shareLabel;

  /// Server-side moderation state, broadcast via LiveKit participant
  /// metadata (set by get_channel_token / moderate_user).
  final bool isServerMuted;
  final bool isServerDeafened;

  /// A screen share whose window is minimised, so its picture is standing
  /// still — see `VoiceAttributes.isSharePaused`. False for anything else.
  final bool isSharePaused;

  /// What a screen share says it is sending, as the badge words it
  /// ("1080p · 60fps") — see `VoiceAttributes.sentPictureOf`. Null when it
  /// has not said, and for anything that is not a screen share.
  final String? shareQuality;

  /// The streams this connection is watching, by share identity — see
  /// `VoiceAttributes.watchingOf`. A stream's tile reads it back the other
  /// way round, to show who is in front of it.
  final Set<String> watching;

  const ParticipantInfo({
    required this.identity,
    required this.userId,
    required this.name,
    this.isSpeaking = false,
    this.isMicrophoneEnabled = false,
    this.isCameraEnabled = false,
    this.isLocal = false,
    this.isScreenshare = false,
    this.isSoundShare = false,
    this.shareLabel = '',
    this.isDeafened = false,
    this.isSharingScreen = false,
    this.isSharingSound = false,
    this.isServerMuted = false,
    this.isServerDeafened = false,
    this.isSharePaused = false,
    this.shareQuality,
    this.watching = const {},
  });

  /// The same connection, watching [watching] instead. For folding several
  /// of one person's devices into one row without losing what each watches.
  ParticipantInfo withWatching(Set<String> watching) => ParticipantInfo(
    identity: identity,
    userId: userId,
    name: name,
    isSpeaking: isSpeaking,
    isMicrophoneEnabled: isMicrophoneEnabled,
    isCameraEnabled: isCameraEnabled,
    isLocal: isLocal,
    isScreenshare: isScreenshare,
    isSoundShare: isSoundShare,
    shareLabel: shareLabel,
    isDeafened: isDeafened,
    isSharingScreen: isSharingScreen,
    isSharingSound: isSharingSound,
    isServerMuted: isServerMuted,
    isServerDeafened: isServerDeafened,
    isSharePaused: isSharePaused,
    shareQuality: shareQuality,
    watching: watching,
  );

  /// Whether this is a share rather than a person in the call. Anything
  /// counting or listing people drops these: a share is one member's extra
  /// connection, and would otherwise show up as a second member.
  bool get isShare => isScreenshare || isSoundShare;

  /// Parses the moderation flags out of a LiveKit participant metadata
  /// string (`{"muted":bool,"deafened":bool}`). Returns (false, false) for
  /// missing or malformed metadata.
  static ({bool muted, bool deafened}) moderationFromMetadata(
    String? metadata,
  ) {
    if (metadata == null || metadata.isEmpty) {
      return (muted: false, deafened: false);
    }
    try {
      final decoded = jsonDecode(metadata);
      if (decoded is! Map<String, dynamic>) {
        return (muted: false, deafened: false);
      }
      return (
        muted: decoded['muted'] == true,
        deafened: decoded['deafened'] == true,
      );
    } catch (_) {
      return (muted: false, deafened: false);
    }
  }
}
