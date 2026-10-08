import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/apis/profile_api.dart';
import '../../../../../data/constants.dart';
import '../../../../../data/repositories/session_repository.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/pick_picture.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Over the widget budget and one job: a form: name and picture, saved
/// together.
///
/// Edit your profile on the **selected server**.
///
/// Each server is its own identity, so this changes how you appear there and
/// nowhere else — the modal says so rather than implying a global profile.
class ProfileEditModal extends StatefulWidget {
  const ProfileEditModal({super.key});

  @override
  State<ProfileEditModal> createState() => _ProfileEditModalState();
}

class _ProfileEditModalState extends State<ProfileEditModal> {
  static const double _avatarSize = 84;

  late final TextEditingController _nameController;
  Uint8List? _pickedAvatar;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = context.read<ServerCubit>().state.selectedServer?.user;
    _nameController = TextEditingController(text: user?.displayName ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    setState(() => _error = null);
    final picked = await pickPicture(context: 'Profile');
    if (!mounted) return;
    // Cancelled: neither bytes nor a reason, and nothing to change.
    if (picked.bytes == null && picked.error == null) return;
    setState(() {
      _error = picked.error;
      if (picked.bytes != null) _pickedAvatar = picked.bytes;
    });
  }

  Future<void> _save() async {
    final user = context.read<ServerCubit>().state.selectedServer?.user;
    final profile = ProfileApi(session: context.read<SessionRepository>());
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Display name cannot be empty.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    // Avatar first: if it fails there is nothing to roll back, whereas a
    // saved name plus a failed picture would need explaining.
    final picked = _pickedAvatar;
    if (picked != null) {
      final uploaded = await profile.uploadAvatar(picked);
      if (!mounted) return;
      if (!uploaded.success) {
        setState(() {
          _saving = false;
          _error = uploaded.error ?? 'Failed to upload the picture.';
        });
        return;
      }
    }

    if (name != user?.displayName) {
      final saved = await profile.updateProfile(displayName: name);
      if (!mounted) return;
      if (!saved.success) {
        setState(() {
          _saving = false;
          _error = saved.error ?? 'Failed to save your name.';
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
    HelperMethods.showToast(
      title: 'Profile updated',
      description: 'Your profile on this server has been saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final server = context.read<ServerCubit>().state.selectedServer;
    final user = server?.user;
    return AppModal(
      title: 'Edit profile',
      subtitle: 'How you appear on ${server?.name ?? 'this server'}',
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _avatarPicker(themeState, user?.avatarPath, user?.id)),
          const SizedBox(height: 18),
          AppTextField(
            controller: _nameController,
            label: 'Display name',
            hint: 'Your name on this server',
            enabled: !_saving,
            maxLength: 32,
          ),
          const SizedBox(height: 6),
          Text(
            'Each server is a separate identity — this name and picture '
            'apply here only.',
            style: AppText.label.copyWith(color: themeState.textTertiary),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          isLoading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _avatarPicker(
    ThemeState themeState,
    String? currentPath,
    String? userId,
  ) {
    final picked = _pickedAvatar;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // The avatar's own squircle, not a circle: this is a preview of
            // how everybody else will see it, and nowhere else draws it round.
            ClipRRect(
              borderRadius: BorderRadius.circular(
                _avatarSize * K.avatarRadiusRatio,
              ),
              child: picked != null
                  ? Image.memory(
                      picked,
                      width: _avatarSize,
                      height: _avatarSize,
                      fit: BoxFit.cover,
                    )
                  : UserAvatar(
                      avatarPath: currentPath,
                      name: _nameController.text,
                      // By id: seeded by the name, the colour changed with
                      // every letter typed into the field below.
                      seed: userId,
                      size: _avatarSize,
                    ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: themeState.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  mouseCursor: WidgetStateMouseCursor.clickable,
                  customBorder: const CircleBorder(),
                  onTap: _saving ? null : _pickAvatar,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      size: K.iconRow,
                      color: themeState.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          picked != null ? 'New picture ready to save' : 'Change picture',
          style: AppText.label.copyWith(color: themeState.textTertiary),
        ),
      ],
    );
  }
}
