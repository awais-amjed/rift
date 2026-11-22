import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../data/apis/roles_api.dart';
import '../../../../../data/classes/role.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/role_ladder.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../common/loading_dots.dart';
import '../../../../common/server_scope.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// The submenu behind "Roles" — one row per role, ticked when held.
///
/// Everything it draws comes from [ServerMembersCubit], which is live: a role
/// created in the roles editor, or handed out by another admin, shows here
/// without reopening the menu. Rows deliberately don't dismiss — granting two
/// roles in a row is the common case, the same reason the mute toggle leaves
/// the menu up.
///
/// A role the viewer may not hand out or take away — any, for somebody who is
/// not an administrator, one above their rank (or at it, to take away), and
/// the owner's for everybody ([RoleLadder.assignable], [RoleLadder.mayTake]) — is
/// listed and inert rather than hidden. Leaving it out would suggest it does
/// not exist; showing it greyed says the rule that is actually being applied.
class ParticipantRolesMenu extends StatefulWidget {
  final String userId;

  const ParticipantRolesMenu({super.key, required this.userId});

  @override
  State<ParticipantRolesMenu> createState() => _ParticipantRolesMenuState();
}

class _ParticipantRolesMenuState extends State<ParticipantRolesMenu> {
  /// Which role is mid-flight. One at a time: two overlapping writes against
  /// the same member would race on the refresh that follows each of them.
  String? _pendingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The viewer's own roles decide how far up the ladder they reach, and the
    // roster reads roles only for the rows on screen.
    final members = context.read<ServerMembersCubit>();
    final myId = context
        .read<ServerCubit>()
        .state
        .meOn(ServerScope.read(context).serverId)
        ?.id;
    if (myId != null && !members.state.memberRoles.containsKey(myId)) {
      unawaited(members.reloadRolesOf(myId));
    }
  }

  Future<void> _toggle(Role role, bool next) async {
    if (_pendingId != null) return;
    setState(() {
      _pendingId = role.id;
      _error = null;
    });

    final api = RolesApi(ServerScope.read(context));
    final members = context.read<ServerMembersCubit>();

    final result = await api.setMemberRole(
      userId: widget.userId,
      roleId: role.id,
      held: next,
    );

    // `member_roles` announces nothing itself — a `users` row moving does, and
    // the trigger that moves the three cached booleans is what makes one move.
    // A role carrying none of those three would otherwise land silently.
    if (result.success) await members.refresh();
    if (!mounted) return;
    setState(() {
      _pendingId = null;
      _error = result.success ? null : result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final roster = context.watch<ServerMembersCubit>().state;
    final member = roster.byId[widget.userId];

    // An administrator's to hand out, and nobody else's. Selected, so a
    // menu left open while that changes follows it.
    final serverId = ServerScope.of(context).serverId;
    final myBits = context.select<ServerCubit, int>(
      (c) => c.state.permissionsOn(serverId)?.bits ?? 0,
    );
    final isAdministrator = myBits.has(ServerPermission.administrator);
    final myId = context.select<ServerCubit, String?>(
      (c) => c.state.meOn(serverId)?.id,
    );
    // A role goes on up to the viewer's rank and comes off only below it
    // (`app.may_assign_role`, `member_roles_delete`).
    final rank = RoleLadder.rankOf(roster.memberRoles, myId);
    final assignable = {
      for (final role in RoleLadder.assignable(
        roster.roles,
        isAdministrator: isAdministrator,
        rank: rank,
      ))
        role.id,
    };
    final held = {
      for (final role in roster.memberRoles[widget.userId] ?? const <Role>[])
        role.id,
    };
    bool reachable(Role role) => held.contains(role.id)
        ? RoleLadder.mayTake(role, isAdministrator: isAdministrator, rank: rank)
        : assignable.contains(role.id);
    final listed = roster.roles.where((r) => !r.isEveryone).toList();

    final themeState = context.theme;
    if (member == null) {
      return ContextMenuPanel(
        heading: 'Roles',
        children: [_note('Member list still loading.', themeState)],
      );
    }
    if (listed.isEmpty) {
      return ContextMenuPanel(
        heading: 'Roles',
        children: [_note('No roles to hand out yet.', themeState)],
      );
    }

    return ContextMenuPanel(
      heading: 'Roles',
      children: [
        for (final role in listed)
          ContextMenuItem(
            icon: Icons.shield_outlined,
            label: role.name,
            // Inert rather than absent, so the rule is visible. Tapping a
            // role you may not hand out does nothing, which is what the
            // database would have said a round trip later.
            onTap: () {
              if (reachable(role)) _toggle(role, !held.contains(role.id));
            },
            trailing: _trailing(
              role: role,
              isHeld: held.contains(role.id),
              outranked: !reachable(role),
              themeState: themeState,
            ),
          ),
        if (_error != null)
          _note(_error!, themeState, color: CustomColors.error),
      ],
    );
  }

  /// Fixed-size, so the labels stay on one column whether a role is held, in
  /// flight, out of reach, or none of those.
  Widget _trailing({
    required Role role,
    required bool isHeld,
    required bool outranked,
    required ThemeState themeState,
  }) {
    if (_pendingId == role.id) {
      return LoadingDots(color: context.theme.accentBright, dotSize: 4);
    }
    return SizedBox(
      width: 16,
      height: 16,
      child: outranked
          ? Icon(
              Icons.lock_rounded,
              size: K.iconInline,
              color: themeState.textQuaternary,
            )
          : isHeld
          ? Icon(
              Icons.check_rounded,
              size: K.iconRow,
              color: themeState.accentBright,
            )
          : null,
    );
  }

  Widget _note(String text, ThemeState themeState, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontWeight: FontWeight.w400,
          color: color ?? themeState.textTertiary,
        ),
      ),
    );
  }
}
