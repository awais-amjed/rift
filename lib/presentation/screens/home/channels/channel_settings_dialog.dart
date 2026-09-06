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

/// Per-channel settings for a channel manager: the name, and how much history
/// this channel keeps.
///
/// A voice channel gets the name and nothing else — it holds no messages, so
/// there is no history for a retention setting to act on, and showing one would
/// be offering a switch wired to nothing.
///
/// Both retention boxes are three-valued and the helper line under each is what
/// makes that legible: blank inherits the server's number, 0 opts this channel
/// out of it, and a number sets its own. See `002_limits.sql`.
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

  /// Blank when the channel inherits — including when it inherits a server that
  /// keeps everything, because "inherit" is about where the number comes from,
  /// not what it is.
  late final TextEditingController _retentionCtrl = TextEditingController(
    text: widget.channel.retentionDays?.toString() ?? '',
  );
  late final TextEditingController _capCtrl = TextEditingController(
    text: widget.channel.historyCap?.toString() ?? '',
  );

  bool _isLoading = false;
  String? _error;

  String get _name => _nameCtrl.text.trim();
  int? get _retention => LimitInput.parse(_retentionCtrl.text);
  int? get _cap => LimitInput.parse(_capCtrl.text);

  bool get _nameChanged => _name.isNotEmpty && _name != widget.channel.name;
  bool get _retentionChanged => _retention != widget.channel.retentionDays;
  bool get _capChanged => _cap != widget.channel.historyCap;

  bool get _canSubmit =>
      _name.isNotEmpty &&
      _retention != LimitInput.invalid &&
      _cap != LimitInput.invalid &&
      (_nameChanged || _retentionChanged || _capChanged);

  ServerLimits get _serverLimits =>
      context.read<ServerCubit>().state.selectedServer?.limits ??
      ServerLimits.defaults;

  /// What the channel falls back to, spelled out — an admin shouldn't have to
  /// open the server dialog to find out what "inherit" currently means.
  String _inheritHelper(int serverValue, String unit, String whenOff) {
    final fallback = serverValue == ServerLimits.unlimited
        ? whenOff
        : '$serverValue $unit';
    return 'Blank inherits the server setting ($fallback). 0 means no limit '
        'in this channel.';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _retentionCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final retention = _retention;
    final cap = _cap;
    final result = await context.read<ServerCubit>().updateChannel(
      channelId: widget.channel.id,
      name: _nameChanged ? _name : null,
      retentionDays: _retentionChanged ? retention : null,
      clearRetentionDays: _retentionChanged && retention == null,
      historyCap: _capChanged ? cap : null,
      clearHistoryCap: _capChanged && cap == null,
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
            label: 'Channel name',
            hint: 'general',
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onEditingComplete: _submit,
          ),
          if (widget.channel.hasMessages) ...[
            const SizedBox(height: 16),
            LimitField(
              controller: _retentionCtrl,
              label: 'Delete messages older than',
              unit: 'days',
              hint: 'Server setting',
              helper: _inheritHelper(
                _serverLimits.messageRetentionDays,
                'days',
                'keep forever',
              ),
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            LimitField(
              controller: _capCtrl,
              label: 'Keep at most',
              unit: 'messages',
              hint: 'Server setting',
              helper: _inheritHelper(
                _serverLimits.messageHistoryCap,
                'messages',
                'keep everything',
              ),
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
          ],
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
