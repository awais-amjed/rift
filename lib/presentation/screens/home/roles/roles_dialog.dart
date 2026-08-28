import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/role.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/hint_card.dart';
import 'role_editor_dialog.dart';
import 'widgets/role_row.dart';

/// Every role on the server, most senior first.
///
/// Open to anybody. What roles exist and who holds them is not a secret from
/// the people they are exercised on — and a member who cannot see the ladder
/// cannot tell whether the person muting them was meant to be able to.
class RolesDialog extends StatefulWidget {
  const RolesDialog({super.key});

  @override
  State<RolesDialog> createState() => _RolesDialogState();
}

class _RolesDialogState extends State<RolesDialog> {
  List<Role> _roles = const [];
  Map<String, int> _counts = const {};
  bool _isLoading = true;

  /// The rank the viewer's own highest role sits at. Everything at or above it
  /// is out of reach — administrators included, because nobody edits the role
  /// they are standing on.
  int _myRank = 0;

  int get _myPermissions =>
      context
          .read<ServerCubit>()
          .state
          .selectedServer
          ?.user
          ?.permissions
          .bits ??
      0;

  bool get _mayManage => _myPermissions.has(ServerPermission.manageRoles);

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

    final counts = <String, int>{};
    for (final held in assignments.values) {
      for (final role in held) {
        counts[role.id] = (counts[role.id] ?? 0) + 1;
      }
    }

    setState(() {
      _roles = roles;
      _counts = counts;
      _myRank = (assignments[me] ?? const <Role>[]).fold(
        0,
        (max, r) => r.position > max ? r.position : max,
      );
      _isLoading = false;
    });
  }

  Future<void> _edit(Role? role) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        // One below the viewer's own rank, which is the only rank they could
        // give a new role anyway. See RoleEditorDialog on why it is not a field.
        child: RoleEditorDialog(role: role, newPosition: _myRank - 1),
      ),
    );
    if (changed == true) _load();
  }

  /// Editable when the viewer may manage roles at all *and* outranks this one.
  /// The baseline is the exception: it is nobody's role to hold, so its rank is
  /// 0 and only the permission matters.
  bool _locked(Role role) =>
      !_mayManage || (!role.isEveryone && role.position >= _myRank);

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;

    return AppModal(
      title: 'Roles',
      subtitle: 'What each one can do, and who holds it',
      maxWidth: 520,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            if (!_mayManage) ...[
              const HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see what every role does. Changing them needs '
                    'the manage-roles permission.',
              ),
              const SizedBox(height: 12),
            ],
            for (final role in _roles)
              RoleRow(
                themeState: themeState,
                role: role,
                memberCount: _counts[role.id] ?? 0,
                locked: _locked(role),
                onTap: () => _edit(role),
              ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        // A rank of 1 is the lowest a role can sit above the baseline, so
        // somebody at rank 1 has nothing left below them to create.
        if (_mayManage && _myRank > 1)
          AppButton(label: 'New role', onPressed: () => _edit(null)),
      ],
    );
  }
}
