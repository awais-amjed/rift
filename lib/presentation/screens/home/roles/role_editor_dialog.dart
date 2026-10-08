import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/role.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/confirm_dialog.dart';
import 'widgets/permission_matrix.dart';
import 'widgets/role_colour_picker.dart';

/// Create or edit one role.
///
/// Position is not editable here, and that is deliberate rather than missing:
/// rank is the whole of the delegation rule, and a number field next to a name
/// field reads like a display preference. A new role is minted one step below
/// its author, which is the only rank they could give it anyway.
class RoleEditorDialog extends StatefulWidget {
  /// Null to create one.
  final Role? role;

  /// The rank a new role is given — one below the author's own.
  final int newPosition;

  /// The server the role is on, or null for the selected one.
  final String? serverId;

  const RoleEditorDialog({
    super.key,
    this.role,
    required this.newPosition,
    this.serverId,
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

  bool get _canSave => _name.isNotEmpty && _changed && !_isSaving;

  int get _viewerPermissions =>
      context.read<ServerCubit>().state.permissionsOn(widget.serverId)?.bits ??
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
    final cubit = context.read<ServerCubit>();

    final result = _isNew
        ? await cubit
              .createRole(
                name: _name,
                position: widget.newPosition,
                permissions: _permissions,
                color: _color,
                serverId: widget.serverId,
              )
              .then((r) => (success: r.role != null, error: r.error))
        : await cubit.updateRole(
            widget.role!.id,
            name: _name,
            permissions: _permissions,
            color: _color,
            clearColor: _color == null,
            serverId: widget.serverId,
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

    final result = await context.read<ServerCubit>().deleteRole(
      widget.role!.id,
      serverId: widget.serverId,
    );
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
      title: _isNew ? 'New role' : 'Edit role',
      subtitle: _isEveryone
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
            enabled: !_isSaving && !_isEveryone,
            autofocus: _isNew,
            onChanged: (_) => setState(() => _error = null),
          ),
          if (!_isEveryone) ...[
            const SizedBox(height: 16),
            RoleColourPicker(
              value: _color,
              onChanged: _isSaving ? null : (c) => setState(() => _color = c),
            ),
          ],
          PermissionMatrix(
            permissions: _permissions,
            viewerPermissions: _viewerPermissions,
            onChanged: _isSaving
                ? null
                : (permission, value) => setState(() {
                    _permissions = value
                        ? _permissions.with_(permission)
                        : _permissions.without(permission);
                  }),
          ),
        ],
      ),
      actions: [
        if (!_isNew && !_isEveryone)
          AppButton(
            label: 'Delete',
            variant: AppButtonVariant.danger,
            onPressed: _isSaving ? null : _delete,
          ),
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: _isSaving ? 'Saving...' : 'Save',
          isLoading: _isSaving,
          onPressed: _canSave ? _save : null,
        ),
      ],
    );
  }
}
