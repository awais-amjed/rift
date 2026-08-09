import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';

/// Rename one channel. Nothing else about it is editable, so this is a field
/// and a button rather than a settings page.
class RenameChannelDialog extends StatefulWidget {
  final Channel channel;

  const RenameChannelDialog({super.key, required this.channel});

  @override
  State<RenameChannelDialog> createState() => _RenameChannelDialogState();
}

class _RenameChannelDialogState extends State<RenameChannelDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.channel.name,
  );

  bool _isLoading = false;
  String? _error;

  String get _name => _nameCtrl.text.trim();

  /// Nothing to submit until it's both non-empty and actually different —
  /// otherwise the button offers a write that would change nothing.
  bool get _canSubmit => _name.isNotEmpty && _name != widget.channel.name;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await context.read<ServerCubit>().renameChannel(
      channelId: widget.channel.id,
      name: _name,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Rename channel',
      subtitle: '#${widget.channel.name}',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
            onEditingComplete: _submit,
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
          label: _isLoading ? 'Renaming...' : 'Rename',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}
