import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/role.dart';
import '../../../../../data/enums/server_permission.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/services/role_ladder.dart';
import '../../../../common/context_menu/context_menu_item.dart';
import '../../../../common/context_menu/context_menu_panel.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';

/// The submenu behind "Roles" — one row per role, ticked when held.
///
/// Everything it draws comes from [ServerMembersCubit], which is live: a role
/// created in the roles editor, or handed out by another admin, shows here
/// without reopening the menu. Rows deliberately don't dismiss — granting two
/// roles in a row is the common case, the same reason the mute toggle leaves
/// the menu up.
///
/// A role at or above the viewer's own rank is listed and inert rather than
/// hidden. Leaving it out would suggest it does not exist; showing it greyed
/// says the rule that is actually being applied.
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

  Future<void> _toggle(Role role, bool next) async {
    if (_pendingId != null) return;
    setState(() {
      _pendingId = role.id;
      _error = null;
    });

    final serverCubit = context.read<ServerCubit>();
    final members = context.read<ServerMembersCubit>();

    final result = await serverCubit.setMemberRole(
      userId: widget.userId,
      roleId: role.id,
      held: next,
    );

    // `member_roles` is not in the realtime publication — `users` is, and the
    // trigger that moves the three cached booleans is what wakes the watcher.
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

    // An administrator's to hand out, and nobody else's (migration 015).
    final myBits =
        context
            .read<ServerCubit>()
            .state
            .selectedServer
            ?.user
            ?.permissions
            .bits ??
        0;
    final assignable = {
      for (final role in RoleLadder.assignable(
        roster.roles,
        isAdministrator: myBits.has(ServerPermission.administrator),
      ))
        role.id,
    };
    final held = {
      for (final role in roster.memberRoles[widget.userId] ?? const <Role>[])
        role.id,
    };
    final listed = roster.roles.where((r) => !r.isEveryone).toList();

    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
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
                // role you do not outrank does nothing, which is what the
                // database would have said a round trip later.
                onTap: () {
                  if (assignable.contains(role.id)) {
                    _toggle(role, !held.contains(role.id));
                  }
                },
                trailing: _trailing(
                  role: role,
                  isHeld: held.contains(role.id),
                  outranked: !assignable.contains(role.id),
                  themeState: themeState,
                ),
              ),
            if (_error != null)
              _note(_error!, themeState, color: CustomColors.error),
          ],
        );
      },
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
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return SizedBox(
      width: 16,
      height: 16,
      child: outranked
          ? Icon(Icons.lock_rounded, size: 13, color: themeState.textQuaternary)
          : isHeld
          ? Icon(Icons.check_rounded, size: 16, color: themeState.accentBright)
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
