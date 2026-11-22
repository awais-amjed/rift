import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/apis/roles_api.dart';
import '../../../../data/classes/role.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/confirm_dialog.dart';
import '../../../common/server_scope.dart';
import 'widgets/permission_matrix.dart';
import 'widgets/role_colour_picker.dart';

/// Create or edit one role.
///
/// Position is not editable here, and that is deliberate rather than missing:
/// rank is the whole of the delegation rule, and a number field next to a name
/// field reads like a display preference. A new role goes in at the bottom of
/// the ladder, and the Roles page moves it from there.
class RoleEditorDialog extends StatefulWidget {
  /// Null to create one.
  final Role? role;

  /// The rank a new role is given (`RolesPanel._newPosition`).
  final int newPosition;

  /// A role the viewer cannot change — at or above their own, or anybody's
  /// when they are not an administrator. Shown with every control off: a save
  /// the server filters out changes nothing, and this used to close as though
  /// it had saved.
  final bool readOnly;

  const RoleEditorDialog({
    super.key,
    this.role,
    required this.newPosition,
    this.readOnly = false,
  });

  @override
  State<RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<RoleEditorDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.role?.name ?? '',
  );

  late int _permissions = widget.role?.permissions ?? 0;
  late String? _color = widget.role?.color;

  bool _isSaving = false;
  String? _error;

  bool get _isNew => widget.role == null;
  bool get _isEveryone => widget.role?.isEveryone ?? false;

  String get _name => _nameCtrl.text.trim();

  bool get _changed =>
      _isNew ||
      _name != widget.role!.name ||
      _permissions != widget.role!.permissions ||
      _color != widget.role!.color;

  bool get _canSave =>
      !widget.readOnly && _name.isNotEmpty && _changed && !_isSaving;

  /// Whether the fields take input at all.
  bool get _editable => !_isSaving && !widget.readOnly;

  int get _viewerPermissions =>
      context
          .read<ServerCubit>()
          .state
          .permissionsOn(ServerScope.read(context).serverId)
          ?.bits ??
      0;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final api = RolesApi(ServerScope.read(context));

    final result = _isNew
        ? await api
              .createRole(
                name: _name,
                position: widget.newPosition,
                permissions: _permissions,
                color: _color,
              )
              .then((r) => (success: r.role != null, error: r.error))
        : await api.updateRole(
            widget.role!.id,
            name: _name,
            permissions: _permissions,
            color: _color,
            clearColor: _color == null,
          );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isSaving = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Delete ${widget.role!.name}?',
      message:
          'Everybody holding it loses whatever it granted, immediately. The '
          'role itself cannot be brought back.',
      confirmLabel: 'Delete role',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final result = await RolesApi(
      ServerScope.read(context),
    ).deleteRole(widget.role!.id);
    if (!mounted) return;
    if (!result.success) {
      setState(() => _error = result.error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: _isNew
          ? 'New role'
          : widget.readOnly
          ? widget.role!.name
          : 'Edit role',
      subtitle: widget.readOnly
          ? 'You can see what this role does, but not change it: it is at or '
                'above your own role, or changing roles is up to an '
                'administrator.'
          : _isEveryone
          ? 'What everybody can do, before any role is handed out'
          : null,
      maxWidth: 560,
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: 'Name',
            hint: 'Moderator',
            // The baseline is not a role you hand out, so its name is not a
            // label anybody chose — renaming it would only make it harder to
            // recognise in the one place it appears.
            enabled: _editable && !_isEveryone,
            autofocus: _isNew,
            maxLength: Role.maxNameLength,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (!_isEveryone) ...[
            const SizedBox(height: 16),
            RoleColourPicker(
              value: _color,
              onChanged: _editable ? (c) => setState(() => _color = c) : null,
            ),
          ],
          PermissionMatrix(
            permissions: _permissions,
            viewerPermissions: _viewerPermissions,
            onChanged: _editable
                ? (permission, value) => setState(() {
                    _permissions = value
                        ? _permissions.with_(permission)
                        : _permissions.without(permission);
                  })
                : null,
          ),
        ],
      ),
      actions: [
        if (!_isNew && !_isEveryone && !widget.readOnly)
          AppButton(
            label: 'Delete',
            variant: AppButtonVariant.danger,
            onPressed: _isSaving ? null : _delete,
          ),
        AppButton(
          label: widget.readOnly ? 'Close' : 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        ),
        if (!widget.readOnly)
          AppButton(
            label: _isSaving ? 'Saving...' : 'Save',
            isLoading: _isSaving,
            onPressed: _canSave ? _save : null,
          ),
      ],
    );
  }
}
