import '../invite_link.dart';

/// One row of the central directory — a self-hosted server whose admin chose
/// to be findable (schema.md, `public_servers`).
///
/// Everything here is plaintext, and that is the point: a listing is an
/// advertisement. It carries the address and an ordinary invite code, never any
/// authority — joining still goes through the target server's own `register`,
/// exactly as pasting an invite link does.
class PublicServer {
  /// Central's own id for the listing, not the server's.
  final String id;

  final String ownerId;
  final String supabaseUrl;

  /// The server on that project. One Supabase project may host several, so
  /// this is what makes a listing (and an "already joined" check) specific.
  final String serverId;

  final String inviteCode;
  final String name;
  final String? description;
  final String? iconUrl;
  final List<String> tags;

  /// What the operator claimed when they last saved. Central cannot count the
  /// members of a database it has no credentials for, so this is self-reported
  /// and [updatedAt] is how stale it might be.
  final int memberCount;

  final bool isListed;
  final DateTime updatedAt;

  /// The column's `length(description) <= 300`, mirrored so a field can stop
  /// at 300 rather than a save discovering the limit.
  static const maxDescription = 300;

  const PublicServer({
    required this.id,
    required this.ownerId,
    required this.supabaseUrl,
    required this.serverId,
    required this.inviteCode,
    required this.name,
    this.description,
    this.iconUrl,
    this.tags = const [],
    this.memberCount = 0,
    this.isListed = true,
    required this.updatedAt,
  });

  /// The same string an admin would paste from the invite dialog, so the join
  /// path from a listing is the join path from a link.
  String get inviteLink => InviteLink.build(supabaseUrl, inviteCode);

  /// The host alone, for the one line of provenance a browser row can show
  /// before you commit to joining.
  String get host => Uri.tryParse(supabaseUrl)?.host ?? supabaseUrl;

  factory PublicServer.fromJson(Map<String, dynamic> json) {
    return PublicServer(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      supabaseUrl: json['supabase_url'] as String,
      serverId: json['server_id'] as String,
      inviteCode: json['invite_code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      iconUrl: json['icon_url'] as String?,
      tags:
          (json['tags'] as List<dynamic>?)?.map((t) => t as String).toList() ??
          const [],
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
      isListed: json['is_listed'] as bool? ?? true,
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner_id': ownerId,
    'supabase_url': supabaseUrl,
    'server_id': serverId,
    'invite_code': inviteCode,
    'name': name,
    'description': description,
    'icon_url': iconUrl,
    'tags': tags,
    'member_count': memberCount,
    'is_listed': isListed,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };
}

/// The shape of a tag the directory will accept, mirrored from the CHECK in
/// central migration 007 so a malformed one is refused while it is still being
/// typed rather than by a database error on save.
class ServerTags {
  /// Matches `^[a-z0-9-]{2,20}$` — the per-element check on `public_servers.tags`.
  static final _shape = RegExp(r'^[a-z0-9-]{2,20}$');

  /// The column's `cardinality(tags) <= 5`.
  static const maxCount = 5;

  static bool isValid(String tag) => _shape.hasMatch(tag);

  /// Fold free text into a tag, or null if nothing usable survives. Spaces
  /// become hyphens rather than being dropped, so "board games" is one tag
  /// instead of "boardgames".
  static String? normalise(String input) {
    final slug = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return isValid(slug) ? slug : null;
  }
}
