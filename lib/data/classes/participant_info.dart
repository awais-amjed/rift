import 'dart:convert';

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

  /// Server-side moderation state, broadcast via LiveKit participant
  /// metadata (set by get_channel_token / moderate_user).
  final bool isServerMuted;
  final bool isServerDeafened;

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
    this.isServerMuted = false,
    this.isServerDeafened = false,
  });

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
