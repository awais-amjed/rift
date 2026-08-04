import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/avatar_image.dart';
import '../../../../../logic/services/mime_util.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';

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
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Images',
            extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
          ),
        ],
      );
      if (file == null) return;

      final mime = (file.mimeType?.isNotEmpty ?? false)
          ? file.mimeType!
          : mimeFromName(file.name);
      if (!AvatarImage.isSupportedMime(mime)) {
        setState(() => _error = "That file isn't an image we can use.");
        return;
      }

      final source = await file.readAsBytes();
      if (!AvatarImage.isAcceptableSize(source.length)) {
        setState(() => _error = 'That image is too large.');
        return;
      }

      // Downscaled + re-encoded here, so what we upload is what everyone
      // else has to download — see AvatarImage.
      final prepared = await AvatarImage.prepare(source);
      if (!mounted) return;
      if (prepared == null) {
        setState(() => _error = "Couldn't read that image.");
        return;
      }
      setState(() => _pickedAvatar = prepared);
    } catch (e) {
      HelperMethods.printDebug('[Profile] avatar pick failed: $e');
      if (mounted) setState(() => _error = "Couldn't open that file.");
    }
  }

  Future<void> _save() async {
    final serverCubit = context.read<ServerCubit>();
    final user = serverCubit.state.selectedServer?.user;
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
      final uploaded = await serverCubit.uploadAvatar(picked);
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
      final saved = await serverCubit.updateProfile(displayName: name);
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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final server = context.read<ServerCubit>().state.selectedServer;
        final user = server?.user;
        return AppModal(
          title: 'Edit Profile',
          subtitle: 'How you appear on ${server?.name ?? 'this server'}',
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, isError: true),
                const SizedBox(height: 12),
              ],
              Center(child: _avatarPicker(themeState, user?.avatarPath)),
              const SizedBox(height: 18),
              Text(
                'Display Name',
                style: AppText.secondary.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: themeState.textTertiary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                enabled: !_saving,
                maxLength: 32,
                style: AppText.rowQuiet.copyWith(
                  color: themeState.textPrimary,
                  fontSize: 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Your name on this server',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Each server is a separate identity — this name and picture '
                'apply here only.',
                style: AppText.label.copyWith(
                  fontSize: 11,
                  color: themeState.textQuaternary,
                ),
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
      },
    );
  }

  Widget _avatarPicker(ThemeState themeState, String? currentPath) {
    final picked = _pickedAvatar;
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: picked != null
                  ? Image.memory(
                      picked,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    )
                  : UserAvatar(
                      avatarPath: currentPath,
                      name: _nameController.text,
                      size: 84,
                      themeState: themeState,
                    ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Material(
                color: themeState.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _saving ? null : _pickAvatar,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.photo_camera_rounded,
                      size: 15,
                      color: Colors.white,
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
          style: AppText.label.copyWith(
            fontSize: 11,
            color: themeState.textQuaternary,
          ),
        ),
      ],
    );
  }
}
