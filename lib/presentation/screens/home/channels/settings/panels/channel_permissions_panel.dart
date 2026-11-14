import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/apis/channel_overrides_api.dart';
import '../../../../../../data/apis/roles_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/classes/channel_override.dart';
import '../../../../../../data/classes/role.dart';
import '../../../../../../data/enums/server_permission.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/chip_selector.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/server_scope.dart';
import '../../../../settings/widgets/setting_toggle_row.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import 'permissions/override_list.dart';

/// What each role may do in one channel, on top of what it may do on the
/// server (`channel_overrides`).
///
/// A switch at the top for the usual case — a channel only some can post in,
/// or a call only some can speak in — which is the `@everyone` row's one bit;
/// then a role at a time, every bit the channel's kind can override, each
/// blocked, left at its default, or allowed. Saved together, like Access.
///
/// Admin roles are left out: an administrator holds every bit in every
/// channel, so nothing set on one would change anything.
class ChannelPermissionsPanel extends StatefulWidget {
  final Channel channel;

  const ChannelPermissionsPanel({super.key, required this.channel});

  @override
  State<ChannelPermissionsPanel> createState() =>
      _ChannelPermissionsPanelState();
}

class _ChannelPermissionsPanelState extends State<ChannelPermissionsPanel> {
  List<Role> _roles = const [];
  Map<String, ChannelOverride> _original = const {};
  Map<String, ChannelOverride> _draft = const {};
  String? _selectedRoleId;

  bool _isLoading = true;
  bool _failedToLoad = false;
  bool _isSaving = false;
  String? _error;

  Channel get _channel => widget.channel;

  /// The bit the switch at the top stands for.
  ServerPermission get _headline => _channel.hasMessages
      ? ServerPermission.sendMessages
      : ServerPermission.speak;

  Role? get _everyone => _roles.where((r) => r.isEveryone).firstOrNull;

  ChannelOverride _rowFor(String roleId) =>
      _draft[roleId] ?? ChannelOverride(roleId: roleId);

  bool get _changed {
    for (final id in {..._original.keys, ..._draft.keys}) {
      if (_rowFor(id) != (_original[id] ?? ChannelOverride(roleId: id))) {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ServerScope.read(context);
    final results = await Future.wait([
      RolesApi(session).listRoles(),
      ChannelOverridesApi(session).list(_channel.id),
    ]);
    if (!mounted) return;
    final roles = results[0] as List<Role>;
    final overrides = results[1] as Map<String, ChannelOverride>?;
    setState(() {
      _isLoading = false;
      _failedToLoad = overrides == null || roles.isEmpty;
      // `@everyone` first: it is where a channel's rule usually lives.
      _roles = [
        ...roles.where((r) => r.isEveryone),
        ...roles.where(
          (r) => !r.isEveryone && !r.carries(ServerPermission.administrator),
        ),
      ];
      _original = overrides ?? const {};
      _draft = {..._original};
      _selectedRoleId = _everyone?.id;
    });
  }

  void _edit(ChannelOverride row) =>
      setState(() => _draft = {..._draft, row.roleId: row});

  void _setHeadline(bool restricted) {
    final everyone = _everyone;
    if (everyone == null) return;
    _edit(
      _rowFor(everyone.id).withState(
        _headline,
        restricted ? OverrideState.deny : OverrideState.inherit,
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final api = ChannelOverridesApi(ServerScope.read(context));
    for (final id in {..._original.keys, ..._draft.keys}) {
      final row = _rowFor(id);
      if (row == (_original[id] ?? ChannelOverride(roleId: id))) continue;
      final result = await api.set(_channel, row);
      if (!mounted) return;
      if (!result.success) {
        setState(() {
          _isSaving = false;
          _error = result.error;
        });
        return;
      }
      _original = {..._original, id: row};
    }
    setState(() => _isSaving = false);
    HelperMethods.showSuccess(message: 'Permissions saved');
  }

  @override
  Widget build(BuildContext context) {
    final serverId = ServerScope.idOf(context);
    final viewerBits = context.select<ServerCubit, int>(
      (c) => c.state.permissionsOn(serverId)?.bits ?? 0,
    );
    final everyone = _everyone;
    final selected = _roles.where((r) => r.id == _selectedRoleId).firstOrNull;
    final posts = _channel.hasMessages;

    return ManagePanel(
      title: 'Permissions',
      subtitle: 'What each role can do here',
      error: _error,
      footer: [
        AppButton(
          label: _isSaving ? 'Saving...' : 'Save',
          isLoading: _isSaving,
          onPressed: _changed && !_isSaving ? _save : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 16,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 200)
          else if (_failedToLoad || everyone == null)
            const HintCard(
              icon: Icons.cloud_off_rounded,
              text:
                  'Couldn\'t load this channel\'s permissions. The server '
                  'may need updating first.',
            )
          else ...[
            SettingToggleRow(
              title: posts ? 'Read-only' : 'Listen-only',
              description: posts
                  ? 'Only admins, and roles allowed below, can post.'
                  : 'Only admins, and roles allowed below, can speak.',
              value:
                  _rowFor(everyone.id).stateOf(_headline) == OverrideState.deny,
              onChanged: _isSaving || !viewerBits.has(_headline)
                  ? null
                  : _setHeadline,
            ),
            ChipSelector(
              options: [for (final role in _roles) role.name],
              selectedIndex: _roles.indexWhere((r) => r.id == _selectedRoleId),
              onSelected: (i) => setState(() => _selectedRoleId = _roles[i].id),
            ),
            if (selected != null)
              OverrideList(
                type: _channel.channelType,
                role: selected,
                row: _rowFor(selected.id),
                everyone: everyone,
                everyoneRow: _rowFor(everyone.id),
                viewerBits: viewerBits,
                onChanged: _isSaving ? null : _edit,
              ),
            const HintCard(
              icon: Icons.shield_outlined,
              text:
                  'Admins can always do everything. Between two of someone\'s '
                  'roles, allow wins.',
            ),
          ],
        ],
      ),
    );
  }
}
