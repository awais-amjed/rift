import 'channel.dart';
import 'livekit_node.dart';
import 'server_limits.dart';
import 'server_user.dart';

/// Over the helper budget and one job: the server model.
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

  /// The operator limits this server reports (`002_limits.sql`). Never null — a
  /// server that has never had them set, or is too old to have the columns,
  /// reports [ServerLimits.defaults].
  final ServerLimits limits;

  /// Bytes of attachments this server is currently holding (migration 029),
  /// as of the last time its details were fetched.
  ///
  /// Not a limit but the thing [ServerLimits.maxStorageBytes] is judged
  /// against, which is why it lives here rather than beside it: it is
  /// measured, never set, and must not be sent back when limits are saved.
  /// Stale by however long the server has been open — enough to warn
  /// somebody before they pick a file, which is all it is for.
  final int storageUsed;

  /// Every LiveKit this server may hold a call on, default first.
  ///
  /// Empty from a server that has never answered with one, which reads the
  /// same as "just [livekitUrl]" — the default node is that address under
  /// another name, so a one-node server and an unaware one behave alike.
  final List<LiveKitNode> livekitNodes;

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
    this.limits = ServerLimits.defaults,
    this.storageUsed = 0,
    this.livekitNodes = const [],
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
      limits: ServerLimits.fromJson(serverDetails),
      storageUsed: (serverDetails['storage_used'] as num?)?.toInt() ?? 0,
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
      limits: ServerLimits.fromJson(serverData),
      storageUsed: (serverData['storage_used'] as num?)?.toInt() ?? 0,
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
      limits: json['limits'] != null
          ? ServerLimits.fromJson(json['limits'] as Map<String, dynamic>)
          : ServerLimits.defaults,
      storageUsed: (json['storageUsed'] as num?)?.toInt() ?? 0,
      user: json['user'] != null
          ? ServerUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      channels:
          (json['channels'] as List<dynamic>?)
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      livekitNodes:
          (json['livekitNodes'] as List<dynamic>?)
              ?.map((n) => LiveKitNode.fromJson(n as Map<String, dynamic>))
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
    'limits': limits.toJson(),
    'storageUsed': storageUsed,
    'user': user?.toJson(),
    'channels': channels.map((c) => c.toJson()).toList(),
    'livekitNodes': livekitNodes.map((n) => n.toJson()).toList(),
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
    ServerLimits? limits,
    int? storageUsed,
    List<LiveKitNode>? livekitNodes,
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
      limits: limits ?? this.limits,
      storageUsed: storageUsed ?? this.storageUsed,
      user: clearUser ? null : (user ?? this.user),
      channels: channels ?? this.channels,
      livekitNodes: livekitNodes ?? this.livekitNodes,
    );
  }
}
