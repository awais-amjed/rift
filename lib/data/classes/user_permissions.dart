class UserPermissions {
  final bool isServerAdmin;
  final bool isChannelManager;
  final bool canCreateTokens;

  const UserPermissions({
    this.isServerAdmin = false,
    this.isChannelManager = false,
    this.canCreateTokens = false,
  });

  factory UserPermissions.fromJson(Map<String, dynamic> json) {
    return UserPermissions(
      isServerAdmin: json['is_server_admin'] as bool? ?? false,
      isChannelManager: json['is_channel_manager'] as bool? ?? false,
      canCreateTokens: json['can_create_tokens'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'is_server_admin': isServerAdmin,
    'is_channel_manager': isChannelManager,
    'can_create_tokens': canCreateTokens,
  };
}
