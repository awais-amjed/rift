import 'dart:convert';

class ParticipantInfo {
  final String identity;
  final String name;
  final bool isSpeaking;
  final bool isMicrophoneEnabled;
  final bool isCameraEnabled;
  final bool isLocal;
  final bool isScreenshare;

  /// Server-side moderation state, broadcast via LiveKit participant
  /// metadata (set by get_channel_token / moderate_user).
  final bool isServerMuted;
  final bool isServerDeafened;

  const ParticipantInfo({
    required this.identity,
    required this.name,
    this.isSpeaking = false,
    this.isMicrophoneEnabled = false,
    this.isCameraEnabled = false,
    this.isLocal = false,
    this.isScreenshare = false,
    this.isServerMuted = false,
    this.isServerDeafened = false,
  });

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
