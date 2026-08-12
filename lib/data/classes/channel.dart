import '../enums/channel_type.dart';

class Channel {
  final String id;
  final String name;
  final ChannelType channelType;

  /// Per-member messages per rolling 24h in this channel.
  ///
  /// Null is not "unlimited" — it is **inherit**, meaning the server's
  /// `defaultChannelDailyQuota` applies. A channel opts out of a server-wide
  /// quota by setting this to `ServerLimits.unlimited` (0), which is a
  /// different thing from never having set it.
  final int? dailyQuota;

  const Channel({
    required this.id,
    required this.name,
    required this.channelType,
    this.dailyQuota,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String,
      name: json['name'] as String,
      channelType: ChannelType.fromString(
        json['channel_type'] as String? ?? 'text',
      ),
      dailyQuota: (json['daily_quota'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'channel_type': channelType.toJson(),
    'daily_quota': dailyQuota,
  };
}
