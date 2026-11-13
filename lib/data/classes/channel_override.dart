import 'package:equatable/equatable.dart';

import '../enums/channel_type.dart';
import '../enums/server_permission.dart';

/// What one channel allows and denies one role (`channel_overrides`), on top
/// of the role's server-wide bits. A bit in neither is inherited.
///
/// The baseline row is the `@everyone` role's. How the rows add up for a
/// member is the server's (`app.channel_permissions_of`); the client is told
/// the answer per channel (`Channel.myPermissions`) and never works it out.
class ChannelOverride extends Equatable {
  final String roleId;
  final int allow;
  final int deny;

  const ChannelOverride({required this.roleId, this.allow = 0, this.deny = 0});

  /// The three answers a channel can give about [permission].
  OverrideState stateOf(ServerPermission permission) =>
      allow.carries(permission)
      ? OverrideState.allow
      : deny.carries(permission)
      ? OverrideState.deny
      : OverrideState.inherit;

  /// This row with [permission] set to [state] and nothing else moved.
  ChannelOverride withState(ServerPermission permission, OverrideState state) =>
      ChannelOverride(
        roleId: roleId,
        allow: state == OverrideState.allow
            ? allow.with_(permission)
            : allow.without(permission),
        deny: state == OverrideState.deny
            ? deny.with_(permission)
            : deny.without(permission),
      );

  bool get isEmpty => allow == 0 && deny == 0;

  factory ChannelOverride.fromJson(Map<String, dynamic> json) =>
      ChannelOverride(
        roleId: json['role_id'] as String,
        allow: (json['allow'] as num?)?.toInt() ?? 0,
        deny: (json['deny'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'role_id': roleId,
    'allow': allow,
    'deny': deny,
  };

  @override
  List<Object?> get props => [roleId, allow, deny];

  /// The bits a channel of [type] may override, in the order the editor
  /// lists them — `app.channel_perm_mask`'s, which refuses any other. Never
  /// `viewChannel`: who sees a channel is a private channel's member list.
  static List<ServerPermission> overridableIn(ChannelType type) =>
      switch (type) {
        ChannelType.text => const [
          ServerPermission.sendMessages,
          ServerPermission.attachFiles,
          ServerPermission.addReactions,
          ServerPermission.mentionAll,
          ServerPermission.createPolls,
          ServerPermission.pinMessages,
          ServerPermission.manageMessages,
        ],
        ChannelType.voice => const [
          ServerPermission.connect,
          ServerPermission.speak,
          ServerPermission.screenShare,
          ServerPermission.useSoundboard,
          ServerPermission.summonBots,
        ],
      };
}

/// One bit in one channel, for one role.
enum OverrideState { allow, inherit, deny }
