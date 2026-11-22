import 'package:equatable/equatable.dart';

/// One link into a server, as its Invites page lists it (`invites`).
///
/// The code is the secret that lets somebody in, so the page draws only its
/// last few characters ([codeTail]): enough to tell which link was pasted
/// where, not enough to use one read over somebody's shoulder.
class ServerInvite extends Equatable {
  final String id;
  final String code;
  final DateTime createdAt;

  /// Who made it, or null when they have since left or been removed.
  final String? createdBy;

  /// Their name as the server has it, when [createdBy] is still a member.
  final String? creatorName;

  /// Null for a link with no limit.
  final int? maxUses;
  final int uses;

  /// Null for a link that never expires.
  final DateTime? expiresAt;

  final bool isBot;

  /// The role it hands out on top of `@everyone`, if any.
  final String? roleId;

  const ServerInvite({
    required this.id,
    required this.code,
    required this.createdAt,
    this.createdBy,
    this.creatorName,
    this.maxUses,
    this.uses = 0,
    this.expiresAt,
    this.isBot = false,
    this.roleId,
  });

  factory ServerInvite.fromJson(Map<String, dynamic> json) {
    final creator = json['creator'];
    String? name;
    if (creator is Map) {
      final display = creator['display_name'] as String?;
      name = (display != null && display.trim().isNotEmpty)
          ? display
          : creator['username'] as String?;
    }
    return ServerInvite(
      id: json['id'] as String,
      code: json['code'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
      creatorName: name,
      maxUses: (json['max_uses'] as num?)?.toInt(),
      uses: (json['uses'] as num?)?.toInt() ?? 0,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      isBot: json['is_bot'] as bool? ?? false,
      roleId: json['role_id'] as String?,
    );
  }

  /// The end of the code, for telling links apart.
  String get codeTail =>
      code.length <= 4 ? code : '…${code.substring(code.length - 4)}';

  /// Whether it can no longer let anybody in, though the sweep has not taken
  /// it away yet.
  bool expiredAt(DateTime now) => expiresAt != null && !expiresAt!.isAfter(now);

  @override
  List<Object?> get props => [
    id,
    code,
    createdAt,
    createdBy,
    creatorName,
    maxUses,
    uses,
    expiresAt,
    isBot,
    roleId,
  ];
}
