import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/enums/channel_type.dart';
import '../../../../data/repositories/server_repository.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/helper_methods.dart';
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
  final _repository = ServerRepository();
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

    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final createResponse = await _repository.createChannel(
      server.supabaseUrl,
      server.token,
      name: _nameCtrl.text.trim(),
      channelType: _type.name,
    );

    if (!mounted) return;

    if (!createResponse.success) {
      setState(() {
        _error = createResponse.error;
        _isLoading = false;
      });
      return;
    }

    // Refresh channel list
    final detailsResponse = await _repository.getServerDetails(
      server.supabaseUrl,
      server.token,
    );

    if (!mounted) return;

    if (detailsResponse.success) {
      final rawChannels = detailsResponse.data['channels'] as List<dynamic>?;
      final channels =
          rawChannels
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];
      context.read<ServerCubit>().updateServer(server.id, channels: channels);
    }

    HelperMethods.showSuccess(message: 'Channel created!');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.bgSecondaryDark
        : CustomColors.bgSecondaryLight;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;
    final textPrimary = isDark
        ? CustomColors.textPrimaryDark
        : CustomColors.textPrimaryLight;
    final textSecondary = isDark
        ? CustomColors.textSecondaryDark
        : CustomColors.textSecondaryLight;
    final textTertiary = isDark
        ? CustomColors.textTertiaryDark
        : CustomColors.textTertiaryLight;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
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
                  color: textPrimary,
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
                    color: CustomColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: CustomColors.error.withOpacity(0.3),
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
                  color: textTertiary,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? CustomColors.primary
                : isDark
                ? CustomColors.bgTertiaryDark
                : CustomColors.bgTertiaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : isDark
                    ? CustomColors.textSecondaryDark
                    : CustomColors.textSecondaryLight,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Colors.white
                      : isDark
                      ? CustomColors.textSecondaryDark
                      : CustomColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
