import 'channel.dart';
import 'livekit_node.dart';
import 'server_limits.dart';
import 'server_user.dart';

/// One `get_server_details()` reply, parsed once.
///
/// Three paths ask this question — a cold start's login, a background token
/// refresh, and an explicit refresh — and each used to pick its own fields out
/// of the map by hand. They picked different ones: login kept the channels and
/// dropped the limits, the token refresh kept nothing but the token. So a cap
/// an operator set reached only whoever happened to trigger the third path,
/// and `storage_used` reached nobody at all after the moment of joining.
///
/// Parsing it in one place is what stops that recurring: a column added to the
/// function now has exactly one client-side reader to teach.
///
/// **Every field is nullable, and null means the reply did not mention it** —
/// which is not the same as "it is unset". A banned member's reply is their own
/// row and an empty channel list, and turning that into
/// [ServerLimits.defaults] would quietly wipe an operator's caps. Callers hand
/// these straight to `copyWith`, which leaves a null alone.
class ServerDetails {
  final String? name;
  final String? iconUrl;
  final String? livekitUrl;
  final String? supabaseKey;
  final ServerUser? user;
  final List<Channel>? channels;
  final ServerLimits? limits;
  final int? storageUsed;
  final int? maxFileBytes;

  /// Every LiveKit this server may hold a call on, default first. Empty from
  /// a server too old to have a node list, which is the same as "just the one
  /// at [livekitUrl]".
  final List<LiveKitNode>? livekitNodes;

  const ServerDetails({
    this.name,
    this.iconUrl,
    this.livekitUrl,
    this.supabaseKey,
    this.user,
    this.channels,
    this.limits,
    this.storageUsed,
    this.maxFileBytes,
    this.livekitNodes,
  });

  /// `max_attachment_bytes` is the marker for "this reply carries limits".
  /// It is the one limit with no "off" ([ServerLimits.defaultMaxAttachmentBytes]
  /// rather than [ServerLimits.unlimited]), so it is present in every real
  /// payload and absent from the banned-member shape — which makes it the
  /// honest thing to test, rather than any single cap that may legitimately
  /// be missing from an older server.
  factory ServerDetails.fromJson(Map<String, dynamic> json) {
    return ServerDetails(
      name: json['name'] as String?,
      iconUrl: json['icon_url'] as String?,
      livekitUrl: json['livekit_url'] as String?,
      supabaseKey: json['supabase_key'] as String?,
      user: json['user'] != null
          ? ServerUser.fromJson(json['user'] as Map<String, dynamic>)
          : null,
      channels: (json['channels'] as List<dynamic>?)
          ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
          .toList(),
      limits: json.containsKey('max_attachment_bytes')
          ? ServerLimits.fromJson(json)
          : null,
      storageUsed: (json['storage_used'] as num?)?.toInt(),
      maxFileBytes: (json['max_file_bytes'] as num?)?.toInt(),
      livekitNodes: (json['livekit_nodes'] as List<dynamic>?)
          ?.map((n) => LiveKitNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}
