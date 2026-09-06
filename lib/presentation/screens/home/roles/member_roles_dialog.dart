import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/role.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/message_banner.dart';
import 'widgets/role_row.dart';
import '../../../../logic/services/role_ladder.dart';
import '../../../../data/enums/server_permission.dart';

/// Which roles one member holds.
///
/// Each toggle is written the moment it is flipped rather than gathered up
/// behind a Save. Granting a role is not a draft — it takes effect for that
/// person as soon as the row lands, and a dialog that batched it would be
/// showing a state the server does not have.
class MemberRolesDialog extends StatefulWidget {
  final ServerMember member;

  const MemberRolesDialog({super.key, required this.member});

  @override
  State<MemberRolesDialog> createState() => _MemberRolesDialogState();
}

class _MemberRolesDialogState extends State<MemberRolesDialog> {
  List<Role> _roles = const [];
  Set<String> _held = {};

  /// Which of [_roles] this viewer may actually hand out. Not the same as the
  /// ones they may *edit* — see [RoleLadder.assignable].
  Set<String> _assignable = const {};
  bool _isLoading = true;
  String? _busyId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    final roles = await cubit.listRoles();
    final assignments = await cubit.listMemberRoles();
    if (!mounted) return;

    setState(() {
      _roles = roles.where((r) => !r.isEveryone).toList();
      _assignable = {
        for (final role in RoleLadder.assignable(
          roles,
          isAdministrator:
              (cubit.state.selectedServer?.user?.permissions.bits ?? 0).has(
                ServerPermission.administrator,
              ),
        ))
          role.id,
      };
      _held = {
        for (final r in assignments[widget.member.id] ?? const <Role>[]) r.id,
      };
      _isLoading = false;
    });
  }

  Future<void> _toggle(Role role) async {
    final held = _held.contains(role.id);
    setState(() {
      _busyId = role.id;
      _error = null;
    });

    final result = await context.read<ServerCubit>().setMemberRole(
      userId: widget.member.id,
      roleId: role.id,
      held: !held,
    );
    if (!mounted) return;

    setState(() {
      _busyId = null;
      if (result.success) {
        held ? _held.remove(role.id) : _held.add(role.id);
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return AppModal(
      title: 'Roles',
      subtitle: widget.member.displayName,
      maxWidth: 460,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            MessageBanner(message: _error!, kind: MessageBannerKind.error),
            const SizedBox(height: 12),
          ],
          if (_isLoading)
            const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_roles.isEmpty)
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
            for (final role in _roles)
              Opacity(
                opacity: _busyId == role.id ? 0.5 : 1,
                child: Row(
                  children: [
                    Expanded(
                      child: RoleRow(
                        role: role,
                        // An administrator may hand out a role at their own
                        // rank, which is how the only admin on a server makes
                        // a second one. Everybody else is strictly below.
                        locked: !_assignable.contains(role.id),
                      ),
                    ),
                    Checkbox(
                      value: _held.contains(role.id),
                      onChanged:
                          !_assignable.contains(role.id) || _busyId != null
                          ? null
                          : (_) => _toggle(role),
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
