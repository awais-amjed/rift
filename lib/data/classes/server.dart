import 'channel.dart';
import 'server_user.dart';

class Server {
  final String id;
  final String name;
  final String? iconUrl;
  final String supabaseUrl;
  final String? supabaseKey;
  final String? livekitUrl;
  final String token;
  final ServerUser? user;
  final List<Channel> channels;

  const Server({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.supabaseUrl,
    this.supabaseKey,
    this.livekitUrl,
    required this.token,
    this.user,
    this.channels = const [],
  });

  /// Create a server from joining an existing one with a token
  factory Server.fromJoin(
    String supabaseUrl,
    String token,
    Map<String, dynamic> serverDetails,
  ) {
    return Server(
      id: serverDetails['server_id'] as String,
      name: serverDetails['name'] as String? ?? 'Server',
      iconUrl: serverDetails['icon_url'] as String?,
      supabaseUrl: supabaseUrl,
      supabaseKey: serverDetails['supabase_key'] as String?,
      livekitUrl: serverDetails['livekit_url'] as String?,
      token: token,
      user: serverDetails['user'] != null
          ? ServerUser.fromJson(serverDetails['user'] as Map<String, dynamic>)
          : null,
      channels:
          (serverDetails['channels'] as List<dynamic>?)
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Create a server from creating a new one
  factory Server.fromCreate(
    String supabaseUrl,
    Map<String, dynamic> serverData,
    String token,
  ) {
    return Server(
      id: serverData['id'] as String,
      name: serverData['name'] as String,
      iconUrl: serverData['icon_url'] as String?,
      supabaseUrl: supabaseUrl,
      supabaseKey: serverData['supabase_key'] as String?,
      livekitUrl: serverData['livekit_url'] as String?,
      token: token,
      user: serverData['user'] != null
          ? ServerUser.fromJson(serverData['user'] as Map<String, dynamic>)
          : null,
      channels:
          (serverData['channels'] as List<dynamic>?)
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'] as String,
      name: json['name'] as String,
      iconUrl: json['iconUrl'] as String?,
      supabaseUrl: json['supabaseUrl'] as String,
      supabaseKey: json['supabaseKey'] as String?,
      livekitUrl: json['livekitUrl'] as String?,
      token: json['token'] as String,
      user: json['user'] != null
          ? ServerUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      channels:
          (json['channels'] as List<dynamic>?)
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconUrl': iconUrl,
    'supabaseUrl': supabaseUrl,
    'supabaseKey': supabaseKey,
    'livekitUrl': livekitUrl,
    'token': token,
    'user': user?.toJson(),
    'channels': channels.map((c) => c.toJson()).toList(),
  };

  Server copyWith({
    String? id,
    String? name,
    String? iconUrl,
    String? supabaseUrl,
    String? supabaseKey,
    String? livekitUrl,
    String? token,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      iconUrl: iconUrl ?? this.iconUrl,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabaseKey: supabaseKey ?? this.supabaseKey,
      livekitUrl: livekitUrl ?? this.livekitUrl,
      token: token ?? this.token,
      user: clearUser ? null : (user ?? this.user),
      channels: channels ?? this.channels,
    );
  }
}
