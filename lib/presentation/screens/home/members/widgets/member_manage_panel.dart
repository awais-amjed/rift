import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../common/confirm_dialog.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../channels/bots/bot_access_dialog.dart';
import '../../roles/member_roles_dialog.dart';
import 'kick_confirm.dart';
import 'member_moderation_row.dart';
import 'ownership_actions.dart';

/// Expanded management controls under a member row: permission toggles
/// (server admins only), mute/deafen moderation buttons (admins and channel
/// managers), and the kick and ban controls.
///
/// This is the only place a ban can be *lifted*. The participant context menu
/// can ban, but it only ever sees people who are connected, and a banned
/// member cannot be — so a toggle there would be a constant. Here the row
/// comes from the member list, which carries the real flag either way.
class MemberManagePanel extends StatelessWidget {
  final ServerMember member;
  final bool isBusy;
  final bool canManagePermissions;
  final bool canModerate;
  final void Function({bool? muted, bool? deafened, bool? banned, bool kick})
  onModerate;

  /// The server this is about, or null for the selected one. Manage server
  /// opens from the rail for any server, and a row there acts on *that* one.
  final String? serverId;

  const MemberManagePanel({
    super.key,
    required this.member,
    required this.isBusy,
    required this.canManagePermissions,
    required this.canModerate,
    required this.onModerate,
    this.serverId,
  });

  /// Bans ask first; lifting one doesn't.
  ///
  /// The asymmetry is the point — a ban cuts someone off mid-sentence and an
  /// unban only gives that back, so only one of the two is worth a speed bump.
  /// A kicked member is offered the ban, not a lift — an invite already lifts
  /// a kick.
  Future<void> _toggleBan(BuildContext context) async {
    if (member.isBanned && !member.isKicked) {
      onModerate(banned: false);
      return;
    }
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Ban ${member.displayName}?',
      message:
          'They lose access to this server immediately, including anything '
          'they are in the middle of. Their messages stay, and you can lift '
          'this again from here.',
      confirmLabel: 'Ban',
      icon: Icons.gavel_rounded,
      isDestructive: true,
    );
    if (confirmed) onModerate(banned: true);
  }

  Future<void> _kick(BuildContext context) async {
    if (await confirmKick(context, member.displayName)) onModerate(kick: true);
  }

  void _openBotAccess(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: BotAccessDialog(bot: member, serverId: serverId),
      ),
    );
  }

  Future<void> _openRoles(BuildContext context) async {
    // The roster draws the change itself — the dialog writes, the doorbell
    // and its own re-read land it — so there is nothing to tell anybody here.
    await showDialog<void>(
      context: context,
      builder: (ctx) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<ServerMembersCubit>()),
        ],
        child: MemberRolesDialog(member: member, serverId: serverId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(
        color: themeState.bgSecondary,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: themeState.borderPrimary),
      ),
      child: Column(
        children: [
          // A bot's roles are beside the point — what it can *read* is the
          // only grant anybody worries about, and it is the one that
          // cannot be taken back.
          if (member.isBot)
            _PanelRow(
              icon: Icons.hearing_rounded,
              label: 'What it can read',
              onTap: isBusy ? null : () => _openBotAccess(context),
            ),
          // The one way in. There used to be three toggles above this for
          // admin, channel manager and invites — the three the old model
          // had — and they wrote roles underneath, so they agreed with
          // this. Two controls for one fact is one of them going stale the
          // first time somebody edits a role.
          if (canManagePermissions && !member.isBot)
            _PanelRow(
              icon: Icons.shield_outlined,
              label: 'Roles',
              onTap: isBusy ? null : () => unawaited(_openRoles(context)),
            ),
          // Owner only, and only for somebody who could hold it. Below
          // roles rather than among them: it is not a role you hand out,
          // it is the one you give up.
          if (OwnershipActions.canTransferTo(
            context.read<ServerCubit>(),
            member,
            serverId: serverId,
          ))
            _PanelRow(
              icon: Icons.workspace_premium_outlined,
              label: 'Transfer ownership',
              onTap: isBusy
                  ? null
                  : () => OwnershipActions.transfer(
                      context,
                      member,
                      serverId: serverId,
                    ),
            ),
          MemberModerationRow(
            member: member,
            isBusy: isBusy,
            canModerate: canModerate,
            canKick:
                context
                    .read<ServerCubit>()
                    .state
                    .permissionsOn(serverId)
                    ?.can(ServerPermission.kickMembers) ??
                false,
            // `BAN_MEMBERS`, which admins hold by implication and a server
            // may also give a moderator role.
            canBan:
                context
                    .read<ServerCubit>()
                    .state
                    .permissionsOn(serverId)
                    ?.can(ServerPermission.banMembers) ??
                false,
            dividerAbove: canManagePermissions,
            onModerate: onModerate,
            onToggleBan: () => _toggleBan(context),
            onKick: () => unawaited(_kick(context)),
          ),
        ],
      ),
    );
  }
}

/// One tappable line in the panel — the two things it opens rather than
/// toggles.
class _PanelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _PanelRow({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      children: [
        Divider(height: 1, color: themeState.borderPrimary),
        InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              spacing: 9,
              children: [
                Icon(icon, size: K.iconRow, color: themeState.textTertiary),
                Expanded(
                  child: Text(
                    label,
                    style: AppText.rowQuiet.copyWith(
                      color: themeState.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: K.iconRow,
                  color: themeState.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
