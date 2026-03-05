import '../enums/channel_type.dart';

class Channel {
  final String id;
  final String name;
  final ChannelType channelType;

  const Channel({
    required this.id,
    required this.name,
    required this.channelType,
  });

  factory Channel.fromJson(Map<String, dynamic> json) {
    return Channel(
      id: json['id'] as String,
      name: json['name'] as String,
      channelType: ChannelType.fromString(
        json['channel_type'] as String? ?? 'text',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'channel_type': channelType.toJson(),
  };
}
