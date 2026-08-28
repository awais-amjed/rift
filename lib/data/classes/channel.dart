import '../enums/channel_type.dart';

class Channel {
  final String id;
  final String name;
  final ChannelType channelType;

  /// Delete messages in this channel older than this many days.
  ///
  /// Null is not "keep forever" — it is **inherit**, meaning the server's
  /// `messageRetentionDays` applies. A channel opts out of a server-wide sweep
  /// by setting this to `ServerLimits.unlimited` (0), which is a different
  /// answer from never having set it.
  ///
  /// Voice channels carry this and ignore it; they have no messages.
  final int? retentionDays;

  /// Keep at most this many messages in this channel, newest first. Null
  /// inherits the server's `messageHistoryCap`; 0 explicitly means no cap.
  final int? historyCap;

  /// Visible only to its members (`channel_members`, or a role granted access).
  ///
  /// Not a display flag. A private channel's key is sealed to a list of people,
  /// so this is the one channel property that is arithmetic rather than a rule
  /// — see ARCHITECTURE.md §4. A client that got it wrong would draw a lock on
  /// a public room, not open a private one.
  final bool isPrivate;

  const Channel({
    required this.id,
    required this.name,
    required this.channelType,
    this.retentionDays,
    this.historyCap,
    this.isPrivate = false,
  });

  /// Whether this channel holds messages at all, and so whether the retention
  /// settings mean anything for it.
  bool get hasMessages => channelType == ChannelType.text;

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String,
      name: json['name'] as String,
      channelType: ChannelType.fromString(
        json['channel_type'] as String? ?? 'text',
      ),
      retentionDays: (json['retention_days'] as num?)?.toInt(),
      historyCap: (json['history_cap'] as num?)?.toInt(),
      isPrivate: json['is_private'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'channel_type': channelType.toJson(),
    'retention_days': retentionDays,
    'history_cap': historyCap,
    'is_private': isPrivate,
  };
}
