import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/apis/roles_api.dart';
import '../../../../data/classes/role.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../logic/services/role_ladder.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/loading_block.dart';
import '../../../common/server_scope.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'widgets/role_row.dart';

/// Which roles one member holds.
///
/// Each toggle is written the moment it is flipped rather than gathered up
/// behind a Save. Granting a role is not a draft — it takes effect for that
/// person as soon as the row lands, and a dialog that batched it would be
/// showing a state the server does not have.
///
/// The roles and which of them [member] holds come from [ServerMembersCubit],
/// so a role renamed or handed out elsewhere while this is open shows here.
class MemberRolesDialog extends StatefulWidget {
  final ServerMember member;

  const MemberRolesDialog({super.key, required this.member});

  @override
  State<MemberRolesDialog> createState() => _MemberRolesDialogState();
}

class _MemberRolesDialogState extends State<MemberRolesDialog> {
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Their chips are normally read already, with the row this was opened
    // from; this covers somebody whose read has not landed.
    final members = context.read<ServerMembersCubit>();
    if (!members.state.memberRoles.containsKey(widget.member.id)) {
      unawaited(members.reloadRolesOf(widget.member.id));
    }
    // And the viewer's own, which decide how far up the ladder they reach.
    final myId = context
        .read<ServerCubit>()
        .state
        .meOn(ServerScope.read(context).serverId)
        ?.id;
    if (myId != null &&
        myId != widget.member.id &&
        !members.state.memberRoles.containsKey(myId)) {
      unawaited(members.reloadRolesOf(myId));
    }
  }

  Future<void> _toggle(Role role, {required bool held}) async {
    setState(() {
      _busyId = role.id;
      _error = null;
    });

    final members = context.read<ServerMembersCubit>();
    final result = await RolesApi(
      ServerScope.read(context),
    ).setMemberRole(userId: widget.member.id, roleId: role.id, held: !held);
    if (result.success) await members.reloadRolesOf(widget.member.id);
    if (!mounted) return;

    setState(() {
      _busyId = null;
      _error = result.success ? null : result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final roles = context.select<ServerMembersCubit, List<Role>>(
      (c) => c.state.roles,
    );
    final heldRoles = context.select<ServerMembersCubit, List<Role>?>(
      (c) => c.state.memberRoles[widget.member.id],
    );
    final serverId = ServerScope.of(context).serverId;
    final isAdministrator = context.select<ServerCubit, bool>(
      (c) =>
          c.state
              .permissionsOn(serverId)
              ?.can(ServerPermission.administrator) ??
          false,
    );

    final myId = context.select<ServerCubit, String?>(
      (c) => c.state.meOn(serverId)?.id,
    );
    final myRoles = context.select<ServerMembersCubit, List<Role>?>(
      (c) => c.state.memberRoles[myId],
    );
    // Where the viewer stands: a role goes on up to it and comes off only
    // below it (`app.may_assign_role`, `member_roles_delete`), so one admin
    // cannot take Admin off another, nor their own top role off themselves.
    final rank = RoleLadder.rankOf({?myId: ?myRoles}, myId);

    final listed = roles.where((r) => !r.isEveryone).toList();
    // Which of them this viewer may actually hand out. Not the same as the
    // ones they may *edit* — see [RoleLadder.assignable].
    final assignable = {
      for (final role in RoleLadder.assignable(
        roles,
        isAdministrator: isAdministrator,
        rank: rank,
      ))
        role.id,
    };
    final held = {for (final role in heldRoles ?? const <Role>[]) role.id};
    // The viewer's own roles not read yet reads as rank 0, every row locked
    // for the moment they take, rather than a spinner a failed read would
    // leave up.
    final isLoading = heldRoles == null;
    bool locked(Role role) => held.contains(role.id)
        ? !RoleLadder.mayTake(
            role,
            isAdministrator: isAdministrator,
            rank: rank,
          )
        : !assignable.contains(role.id);

    return AppModal(
      title: 'Roles',
      subtitle: widget.member.displayName,
      maxWidth: 460,
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const LoadingBlock(height: 160)
          else if (listed.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'This server has no roles to hand out yet.',
                  style: AppText.secondary.copyWith(
                    color: themeState.textTertiary,
                  ),
                ),
              ),
            )
          else
            for (final role in listed)
              Opacity(
                opacity: _busyId == role.id ? 0.5 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: RoleRow(role: role, locked: locked(role)),
                    ),
                    Checkbox(
                      value: held.contains(role.id),
                      onChanged: locked(role) || _busyId != null
                          ? null
                          : (_) => _toggle(role, held: held.contains(role.id)),
                    ),
                  ],
                ),
              ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Done',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
