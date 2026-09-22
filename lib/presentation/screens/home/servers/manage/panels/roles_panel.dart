import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/role.dart';
import '../../../../../../data/enums/server_permission.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/services/role_ladder.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../roles/role_editor_dialog.dart';
import '../../../roles/widgets/role_row.dart';
import '../widgets/manage_panel.dart';

/// Over the widget budget and one job: the role ladder and the actions on it.
///
/// Every role on the server, most senior first.
///
/// Open to anybody. What roles exist and who holds them is not a secret from
/// the people they are exercised on — and a member who cannot see the ladder
/// cannot tell whether the person muting them was meant to be able to.
class RolesPanel extends StatefulWidget {
  const RolesPanel({super.key});

  @override
  State<RolesPanel> createState() => _RolesPanelState();
}

class _RolesPanelState extends State<RolesPanel> {
  List<Role> _roles = const [];
  Map<String, int> _counts = const {};
  bool _isLoading = true;

  /// The rank the viewer's own highest role sits at. Everything at or above it
  /// is out of reach — administrators included, because nobody edits the role
  /// they are standing on.
  int _myRank = 0;
  String? _movingId;

  int get _myPermissions => context.read<ServerCubit>().state.myPermissionBits;

  /// Administrators only (015). There used to be a bit for this; a ladder
  /// anybody holding a bit could reshape was a ladder nobody had chosen.
  bool get _mayManage => _myPermissions.has(ServerPermission.administrator);

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
      _myRank = RoleLadder.rankOf(assignments, me);
      _isLoading = false;
    });
  }

  /// Where a new role goes: one rung above the highest one already beneath the
  /// viewer, so it lands at the top of what they can manage without landing on
  /// anything. Capped one below their own rank, which is the only ceiling the
  /// delegation rule allows.
  int get _newPosition {
    final below = _manageable.map((r) => r.position);
    final top = below.isEmpty ? 0 : below.reduce((a, b) => a > b ? a : b);
    return top + 1 < _myRank ? top + 1 : _myRank - 1;
  }

  /// Everything the viewer may reorder, most senior first.
  List<Role> get _manageable =>
      RoleLadder.below(_roles, _myRank, isAdministrator: _mayManage);

  Future<void> _edit(Role? role) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BlocProvider.value(
        value: context.read<ServerCubit>(),
        child: RoleEditorDialog(role: role, newPosition: _newPosition),
      ),
    );
    if (changed == true) await _load();
  }

  /// Swap two adjacent roles' positions.
  ///
  /// A swap rather than a renumber, which is why 024 spaced the ladder out: two
  /// roles sharing a rung cannot be ordered by swapping, and renumbering the
  /// band would need more room below the viewer than a dense ladder has.
  Future<void> _move(Role role, {required bool up}) async {
    final ladder = _manageable;
    final index = ladder.indexWhere((r) => r.id == role.id);
    final neighbourIndex = up ? index - 1 : index + 1;
    if (index < 0 || neighbourIndex < 0 || neighbourIndex >= ladder.length) {
      return;
    }
    final neighbour = ladder[neighbourIndex];
    if (neighbour.position == role.position) return;

    setState(() => _movingId = role.id);
    final cubit = context.read<ServerCubit>();

    // Two writes for one swap, and neither result was being looked at. If the
    // second is refused — the connection drops, or somebody else reshaped the
    // ladder underneath us — the first has already landed and both roles claim
    // the same position. That is a ladder nobody chose, and `RoleLadder` reads
    // positions to decide who outranks whom.
    //
    // Putting the first one back is the best this side can do; the real fix is
    // a swap that happens in one statement on the server, which does not exist
    // yet. Either way `_load` below shows what actually happened rather than
    // what was asked for.
    final moved = await cubit.updateRole(role.id, position: neighbour.position);
    if (moved.success) {
      final swapped = await cubit.updateRole(
        neighbour.id,
        position: role.position,
      );
      if (!swapped.success) {
        await cubit.updateRole(role.id, position: role.position);
      }
    }
    if (!mounted) return;
    setState(() => _movingId = null);
    await _load();
  }

  /// Editable when the viewer may manage roles at all *and* outranks this one.
  /// The baseline is the exception: it is nobody's role to hold, so its rank is
  /// 0 and only the permission matters.
  bool _mayMove(Role role) =>
      _movingId == null &&
      !role.isEveryone &&
      !_locked(role) &&
      _manageable.length > 1;

  bool _locked(Role role) =>
      !_mayManage || (!role.isEveryone && role.position >= _myRank);

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Roles',
      subtitle: 'What each one can do, and who holds it',
      footer: [
        // A rank of 1 is the lowest a role can sit above the baseline, so
        // somebody at rank 1 has nothing left below them to create.
        if (_mayManage && _myRank > 1)
          AppButton(label: 'New role', onPressed: () => _edit(null)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 180)
          else ...[
            if (!_mayManage) ...[
              const HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see what every role does. Changing them is an '
                    'administrator\'s.',
              ),
              const SizedBox(height: 12),
            ],
            for (final role in _roles)
              RoleRow(
                role: role,
                memberCount: _counts[role.id] ?? 0,
                locked: _locked(role),
                onTap: () => _edit(role),
                // Reordering is only offered where it means something: the
                // baseline is not a rung on the ladder, it is the ground, and
                // a role you cannot manage is not yours to move past another.
                onMoveUp: _mayMove(role) ? () => _move(role, up: true) : null,
                onMoveDown: _mayMove(role)
                    ? () => _move(role, up: false)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}
