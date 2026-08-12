import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/channel.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/services/limit_input.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/limit_field.dart';
import '../../../common/message_banner.dart';

/// Per-channel settings for a channel manager: the name, and how many messages
/// a member may send here per day.
///
/// The quota box is three-valued and the helper line under it is what makes
/// that legible — blank inherits the server's default, 0 opts this channel out
/// of that default, and a number sets its own. See migration 007.
class ChannelSettingsDialog extends StatefulWidget {
  final Channel channel;

  const ChannelSettingsDialog({super.key, required this.channel});

  @override
  State<ChannelSettingsDialog> createState() => _ChannelSettingsDialogState();
}

class _ChannelSettingsDialogState extends State<ChannelSettingsDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.channel.name,
  );

  /// Blank when the channel inherits — including when it inherits an unlimited
  /// default, because "inherit" is about where the number comes from, not what
  /// it is.
  late final TextEditingController _quotaCtrl = TextEditingController(
    text: widget.channel.dailyQuota?.toString() ?? '',
  );

  bool _isLoading = false;
  String? _error;

  String get _name => _nameCtrl.text.trim();
  int? get _quota => LimitInput.parse(_quotaCtrl.text);

  bool get _nameChanged => _name.isNotEmpty && _name != widget.channel.name;
  bool get _quotaChanged => _quota != widget.channel.dailyQuota;

  bool get _canSubmit =>
      _name.isNotEmpty &&
      _quota != LimitInput.invalid &&
      (_nameChanged || _quotaChanged);

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quotaCtrl.dispose();
    super.dispose();
  }

  /// What the channel falls back to, spelled out — an admin shouldn't have to
  /// open the server dialog to find out what "inherit" currently means.
  String get _inheritHelper {
    final limits =
        context.read<ServerCubit>().state.selectedServer?.limits ??
        ServerLimits.defaults;
    final fallback = limits.defaultChannelDailyQuota == ServerLimits.unlimited
        ? 'no limit'
        : '${limits.defaultChannelDailyQuota} per day';
    return 'Blank inherits the server default ($fallback). '
        '0 means no limit in this channel.';
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final quota = _quota;
    final result = await context.read<ServerCubit>().updateChannel(
      channelId: widget.channel.id,
      name: _nameChanged ? _name : null,
      dailyQuota: _quotaChanged ? quota : null,
      clearDailyQuota: _quotaChanged && quota == null,
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
      title: 'Channel settings',
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
          const SizedBox(height: 16),
          LimitField(
            controller: _quotaCtrl,
            label: 'Messages per member',
            unit: 'per day',
            hint: 'Server default',
            helper: _inheritHelper,
            enabled: !_isLoading,
            onChanged: (_) => setState(() {}),
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
          label: _isLoading ? 'Saving...' : 'Save',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}
