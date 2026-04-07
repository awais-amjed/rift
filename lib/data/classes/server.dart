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

  /// The Ed25519 key derivation version for this server (e.g. 'v1', 'v2').
  /// Incremented on key rotation.
  final String keyVersion;

  /// When the current [token] was last obtained from the server.
  /// Used to trigger a proactive background re-auth before the token expires.
  final DateTime tokenIssuedAt;

  /// True when more than 50 minutes have passed since [tokenIssuedAt].
  /// With a 1-hour server TTL this leaves a 10-minute window for a silent
  /// background re-auth before the token actually expires.
  bool get isTokenNearExpiry =>
      DateTime.now().difference(tokenIssuedAt) > const Duration(minutes: 50);

  Server({
    required this.id,
    required this.name,
    this.iconUrl,
    required this.supabaseUrl,
    this.supabaseKey,
    this.livekitUrl,
    required this.token,
    this.user,
    this.channels = const [],
    this.keyVersion = 'v1',
    DateTime? tokenIssuedAt,
  }) : tokenIssuedAt = tokenIssuedAt ?? DateTime.now();

  /// Create a server from joining an existing one with a token
  factory Server.fromJoin(
    String supabaseUrl,
    String token,
    Map<String, dynamic> serverDetails, {
    String keyVersion = 'v1',
  }) {
    return Server(
      id: serverDetails['server_id'] as String,
      name: serverDetails['name'] as String? ?? 'Server',
      iconUrl: serverDetails['icon_url'] as String?,
      supabaseUrl: supabaseUrl,
      supabaseKey: serverDetails['supabase_key'] as String?,
      livekitUrl: serverDetails['livekit_url'] as String?,
      token: token,
      keyVersion: keyVersion,
      tokenIssuedAt: DateTime.now(),
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
      keyVersion: 'v1',
      tokenIssuedAt: DateTime.now(),
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
      keyVersion: json['keyVersion'] as String? ?? 'v1',
      // Default to epoch so persisted servers without this field are treated
      // as having a stale token — the reactive fallback handles first expiry.
      tokenIssuedAt: json['tokenIssuedAt'] != null
          ? DateTime.parse(json['tokenIssuedAt'] as String)
          : DateTime.fromMillisecondsSinceEpoch(0),
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
    'keyVersion': keyVersion,
    'tokenIssuedAt': tokenIssuedAt.toIso8601String(),
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
    String? keyVersion,
    DateTime? tokenIssuedAt,
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
      keyVersion: keyVersion ?? this.keyVersion,
      // If the token changed, stamp a fresh issue time; otherwise keep existing.
      tokenIssuedAt: token != null
          ? DateTime.now()
          : (tokenIssuedAt ?? this.tokenIssuedAt),
      user: clearUser ? null : (user ?? this.user),
      channels: channels ?? this.channels,
    );
  }
}
