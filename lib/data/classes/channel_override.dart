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

  /// What "Default" comes to for [permission] in the editor: whether someone
  /// holding [serverBits] gets it here when their role's own row leaves it
  /// alone. For the `@everyone` row, [serverBits] is that role's and
  /// [everyoneRow] is null; for another role, it is both roles' bits and the
  /// channel's `@everyone` row, which applies first.
  ///
  /// Display only, like [resultFor].
  ///
  /// `app.apply_channel_overrides`' steps for someone with
  /// just those roles, so the editor can say what leaving a bit alone means.
  /// What a member can actually do is still the server's answer.
  static bool defaultFor(
    ServerPermission permission, {
    required int serverBits,
    ChannelOverride? everyoneRow,
  }) {
    if (serverBits.carries(ServerPermission.administrator)) return true;
    return switch (everyoneRow?.stateOf(permission) ?? OverrideState.inherit) {
      OverrideState.allow => true,
      OverrideState.deny => false,
      OverrideState.inherit => serverBits.carries(permission),
    };
  }

  /// What [row] comes to for [permission]: its own answer, or [defaultFor]
  /// where it leaves the bit alone. Arguments as there; for the `@everyone`
  /// role, [row] is its row and [everyoneRow] null.
  static bool resultFor(
    ServerPermission permission, {
    required ChannelOverride row,
    required int serverBits,
    ChannelOverride? everyoneRow,
  }) => switch (row.stateOf(permission)) {
    OverrideState.allow => true,
    OverrideState.deny => false,
    OverrideState.inherit => defaultFor(
      permission,
      serverBits: serverBits,
      everyoneRow: everyoneRow,
    ),
  };

  /// The bit [permission] cannot be used without in a channel, if any: a
  /// file, a poll and `@all` all go out inside a message, speaking and
  /// sharing happen inside the call, and a clip is sound in it, so Listen-only
  /// takes the soundboard too (`SoundboardCubit`). A chain: the soundboard
  /// needs Speak, which needs Connect. The editor shows such a bit blocked
  /// while what it needs is, without storing it. Summoning a bot is not
  /// here: `summon_bot_to_voice` asks only for itself.
  static ServerPermission? needs(ServerPermission permission) =>
      switch (permission) {
        ServerPermission.attachFiles ||
        ServerPermission.createPolls ||
        ServerPermission.mentionAll => ServerPermission.sendMessages,
        ServerPermission.speak ||
        ServerPermission.screenShare => ServerPermission.connect,
        ServerPermission.useSoundboard => ServerPermission.speak,
        _ => null,
      };

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
