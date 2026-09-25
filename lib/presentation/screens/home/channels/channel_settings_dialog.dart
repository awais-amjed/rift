import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/classes/server_limits.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/limit_input.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/limit_field.dart';
import 'widgets/voice_region_field.dart';

/// Per-channel settings for a channel manager: the name, how much history
/// this channel keeps, and — for a voice channel — which LiveKit its calls
/// are held on.
///
/// The two halves are exclusive, because each is wired to nothing on the
/// other kind. A voice channel holds no messages, so a retention setting
/// there would act on nothing; a text channel holds no calls, so a region
/// would name where nothing happens.
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

  /// Null is "automatic", which is a real answer rather than an unset one —
  /// so the change check compares against the channel's own value rather than
  /// testing for null.
  late String? _nodeId = widget.channel.livekitNodeId;

  bool _isLoading = false;
  String? _error;

  String get _name => _nameCtrl.text.trim();
  int? get _retention => LimitInput.parse(_retentionCtrl.text);
  int? get _cap => LimitInput.parse(_capCtrl.text);

  bool get _nameChanged => _name.isNotEmpty && _name != widget.channel.name;
  bool get _retentionChanged => _retention != widget.channel.retentionDays;
  bool get _capChanged => _cap != widget.channel.historyCap;
  bool get _nodeChanged => _nodeId != widget.channel.livekitNodeId;

  /// Whether to ask the server to move a call that may be running.
  ///
  /// **Asked rather than decided here.** This used to test
  /// `channel.voiceNodeId`, which is only refreshed by `get_server_details`
  /// — and nothing refreshes it when a *call starts*, so the field is null
  /// exactly when a call has just begun, which is when somebody is most
  /// likely to move it. The pin saved and two people stayed where they were.
  ///
  /// The server is the only party that knows, and it answers `no_call`
  /// harmlessly when there is nothing up, so the honest thing is to always
  /// ask when a region was explicitly chosen.
  bool get _shouldMoveLiveCall =>
      widget.channel.voiceNodeId == null ||
      widget.channel.voiceNodeId != _nodeId;

  bool get _canSubmit =>
      _name.isNotEmpty &&
      _retention != LimitInput.invalid &&
      _cap != LimitInput.invalid &&
      (_nameChanged || _retentionChanged || _capChanged || _nodeChanged);

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
      livekitNodeId: _nodeChanged ? _nodeId : null,
      clearLivekitNodeId: _nodeChanged && _nodeId == null,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }

    // A call that is already up does not follow the setting on its own — a
    // room cannot migrate, so moving one means everybody in it reconnecting,
    // and that only happens because somebody asked for it. Saving a different
    // region while a call is running *is* asking.
    //
    // Asked on every explicit region change, because only the server knows
    // whether a call is up: see [_shouldMoveLiveCall]. With nothing running
    // this costs one request that answers `no_call`.
    if (_nodeChanged && _nodeId != null && _shouldMoveLiveCall) {
      final moved = await context.read<ServerCubit>().moveCall(
        channelId: widget.channel.id,
        nodeId: _nodeId!,
      );
      if (!mounted) return;
      if (!moved.success) {
        // The setting is saved; only the live call stayed put. Say which, or
        // the next call landing correctly reads as the error fixing itself.
        setState(() {
          _isLoading = false;
          _error =
              '${moved.error ?? 'Could not move the call that is running.'} '
              'The region is saved and the next call will use it.';
        });
        return;
      }
    }

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Channel settings',
      subtitle: '#${widget.channel.name}',
      error: _error,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: 'Channel name',
            hint: 'general',
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
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
              onChanged: (_) => setState(() => _error = null),
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
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
          if (!widget.channel.hasMessages) ...[
            const SizedBox(height: 16),
            VoiceRegionField(
              nodes:
                  context.read<ServerCubit>().state.selectedServer
                      ?.livekitNodes ??
                  const [],
              selectedNodeId: _nodeId,
              liveNodeId: widget.channel.voiceNodeId,
              enabled: !_isLoading,
              onChanged: (value) => setState(() {
                _nodeId = value;
                _error = null;
              }),
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
