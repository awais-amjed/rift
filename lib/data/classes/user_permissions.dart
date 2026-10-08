import 'package:equatable/equatable.dart';

import '../enums/server_permission.dart';

/// What a member may do on a server. The UI reads it only to hide what would be
/// refused; the server enforces every one of these itself.
class UserPermissions extends Equatable {
  final bool isServerAdmin;
  final bool isChannelManager;
  final bool canCreateTokens;

  /// Whether this member holds the server's owner role (`roles.is_owner`) — a
  /// fourth cached column beside the three above, kept by the same trigger.
  /// Not a permission bit: an owner is an administrator who can also end the
  /// server or hand it on, and those two are gated on this alone.
  final bool isOwner;

  /// Everything this member holds, as `my_permissions()` returned it.
  ///
  /// The three booleans above are a *cache* of three of these bits, kept by a
  /// trigger since 018. They stay because every policy and every older client
  /// reads them; anything that needs one of the other nineteen reads this.
  ///
  /// Zero for a member whose server predates the ladder, which is why the booleans are
  /// still the answer for the three questions they can answer.
  final int bits;

  const UserPermissions({
    this.isServerAdmin = false,
    this.isChannelManager = false,
    this.canCreateTokens = false,
    this.isOwner = false,
    this.bits = 0,
  });

  /// Whether this member holds [permission]. Falls back to the cached boolean
  /// where one exists, so a server too old to have `my_permissions()` still
  /// answers the three questions it always could.
  bool can(ServerPermission permission) {
    if (bits != 0) return bits.has(permission);
    return switch (permission) {
      ServerPermission.administrator => isServerAdmin,
      ServerPermission.manageChannels => isServerAdmin || isChannelManager,
      ServerPermission.createInvite => isServerAdmin || canCreateTokens,
      _ => isServerAdmin,
    };
  }

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      isServerAdmin: json['is_server_admin'] as bool? ?? false,
      isChannelManager: json['is_channel_manager'] as bool? ?? false,
      canCreateTokens: json['can_create_tokens'] as bool? ?? false,
      isOwner: json['is_owner'] as bool? ?? false,
      bits: (json['permission_bits'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_server_admin': isServerAdmin,
    'is_channel_manager': isChannelManager,
    'can_create_tokens': canCreateTokens,
    'is_owner': isOwner,
    'permission_bits': bits,
  };

  UserPermissions copyWith({
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
    bool? isOwner,
    int? bits,
  }) {
    return UserPermissions(
      isServerAdmin: isServerAdmin ?? this.isServerAdmin,
      isChannelManager: isChannelManager ?? this.isChannelManager,
      canCreateTokens: canCreateTokens ?? this.canCreateTokens,
      isOwner: isOwner ?? this.isOwner,
      bits: bits ?? this.bits,
    );
  }

  @override
  List<Object?> get props => [
    isServerAdmin,
    isChannelManager,
    canCreateTokens,
    isOwner,
    bits,
  ];
}
