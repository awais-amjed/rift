import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../data/enums/channel_type.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../common/selectable_surface.dart';
import '../../../theme/app_text.dart';

/// Dialog to create a new channel (text or voice) in the current server.
class CreateChannelDialog extends StatefulWidget {
  const CreateChannelDialog({super.key});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final _nameCtrl = TextEditingController();

  ChannelType _type = ChannelType.text;
  bool _isLoading = false;
  String? _error;

  bool get _canSubmit => _nameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await context.read<ServerCubit>().createChannel(
      name: _nameCtrl.text.trim(),
      channelType: _type.name,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    HelperMethods.showSuccess(message: 'Channel created!');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return AppModal(
          title: 'Create Channel',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, kind: MessageBannerKind.error),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: _nameCtrl,
                label: 'Channel Name',
                hint: 'general',
                enabled: !_isLoading,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'CHANNEL TYPE',
                style: AppText.sectionLabel.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: themeState.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _TypeButton(
                    icon: Icons.tag,
                    label: 'Text',
                    selected: _type == ChannelType.text,
                    onTap: _isLoading
                        ? null
                        : () => setState(() => _type = ChannelType.text),
                  ),
                  const SizedBox(width: 8),
                  _TypeButton(
                    icon: Icons.volume_up,
                    label: 'Voice',
                    selected: _type == ChannelType.voice,
                    onTap: _isLoading
                        ? null
                        : () => setState(() => _type = ChannelType.voice),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
            AppButton(
              label: _isLoading ? 'Creating...' : 'Create Channel',
              isLoading: _isLoading,
              onPressed: _canSubmit && !_isLoading ? _submit : null,
            ),
          ],
        );
      },
    );
  }
}

/// One half of the text/voice segmented control.
class _TypeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _TypeButton({
    required this.icon,
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SelectableSurface(
        selected: selected,
        onTap: onTap,
        borderRadius: BorderRadius.circular(K.radiusButton),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 7,
          children: [
            Icon(icon, size: 15),
            Text(
              label,
              style: AppText.secondary.copyWith(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
