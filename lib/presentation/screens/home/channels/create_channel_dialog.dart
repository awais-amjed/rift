import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/enums/channel_type.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import '../../../theme/custom_colors.dart';

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
        return Dialog(
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create Channel',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: themeState.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: CustomColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: CustomColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CustomColors.error,
                        ),
                      ),
                    ),
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

                  // Channel type
                  Text(
                    'CHANNEL TYPE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
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
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: _isLoading ? 'Creating...' : 'Create Channel',
                          isLoading: _isLoading,
                          onPressed: _canSubmit && !_isLoading ? _submit : null,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppButton(
                        label: 'Cancel',
                        variant: AppButtonVariant.secondary,
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

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
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: selected ? themeState.primary : themeState.bgTertiary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: selected ? Colors.white : themeState.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : themeState.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
