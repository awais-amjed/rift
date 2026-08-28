import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/role.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/message_banner.dart';
import 'widgets/role_row.dart';

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
  int _myRank = 0;
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
    final me = cubit.state.selectedServer?.user?.id;
    final roles = await cubit.listRoles();
    final assignments = await cubit.listMemberRoles();
    if (!mounted) return;

    setState(() {
      // The baseline is not a role anybody holds — it is what holding nothing
      // already gets you — so a switch for it would be one that cannot move.
      _roles = roles.where((r) => !r.isEveryone).toList();
      _held = {
        for (final r in assignments[widget.member.id] ?? const <Role>[]) r.id,
      };
      _myRank = (assignments[me] ?? const <Role>[]).fold(
        0,
        (max, r) => r.position > max ? r.position : max,
      );
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
                  style: TextStyle(color: themeState.textTertiary),
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
                        themeState: themeState,
                        role: role,
                        // Rank decides this, not the manage-roles bit alone:
                        // handing out a role you do not outrank is the one
                        // thing the delegation rule exists to stop.
                        locked: role.position >= _myRank,
                      ),
                    ),
                    Checkbox(
                      value: _held.contains(role.id),
                      onChanged: role.position >= _myRank || _busyId != null
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
