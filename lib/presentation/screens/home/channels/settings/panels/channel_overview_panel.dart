import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/channels_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/classes/server_limits.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../../logic/services/limit_input.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/limit_field.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import '../../widgets/voice_region_field.dart';

/// The first page of a channel's settings: the name, how much history this
/// channel keeps, and — for a voice channel — which region its calls are
/// held in.
///
/// [channel] is the live row, so once a save lands and the server's details
/// are read back, the change checks compare against what was just written and
/// Save greys out again. Anything decided *about* the save is taken before it
/// is sent, because that refresh can arrive while it is still in flight.
///
/// The two halves are exclusive, because each is wired to nothing on the
/// other kind. A voice channel holds no messages, so a retention setting
/// there would act on nothing; a text channel holds no calls, so a region
/// would name where nothing happens.
///
/// Both retention boxes are three-valued and the helper line under each is what
/// makes that legible: blank inherits the server's number, 0 opts this channel
/// out of it, and a number sets its own. See `app.enforce_retention`.
class ChannelOverviewPanel extends StatefulWidget {
  final Channel channel;

  const ChannelOverviewPanel({super.key, required this.channel});

  @override
  State<ChannelOverviewPanel> createState() => _ChannelOverviewPanelState();
}

class _ChannelOverviewPanelState extends State<ChannelOverviewPanel> {
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
    final nodeChanged = _nodeChanged;
    final moveLiveCall = _shouldMoveLiveCall;
    final nodeId = _nodeId;
    final result = await ChannelsApi(session: context.read<SessionRepository>())
        .updateChannel(
          channelId: widget.channel.id,
          name: _nameChanged ? _name : null,
          retentionDays: _retentionChanged ? retention : null,
          clearRetentionDays: _retentionChanged && retention == null,
          historyCap: _capChanged ? cap : null,
          clearHistoryCap: _capChanged && cap == null,
          livekitNodeId: nodeChanged ? nodeId : null,
          clearLivekitNodeId: nodeChanged && nodeId == null,
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
    if (nodeChanged && nodeId != null && moveLiveCall) {
      final moved = await context.read<ServerCubit>().moveCall(
        channelId: widget.channel.id,
        nodeId: nodeId,
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

    setState(() => _isLoading = false);
    HelperMethods.showSuccess(message: 'Channel saved');
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Overview',
      subtitle: widget.channel.hasMessages
          ? 'Name and message history'
          : 'Name and where calls are held',
      error: _error,
      footer: [
        AppButton(
          label: _isLoading ? 'Saving...' : 'Save',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: 'Channel name',
            hint: 'general',
            enabled: !_isLoading,
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
                  context
                      .read<ServerCubit>()
                      .state
                      .selectedServer
                      ?.livekitNodes ??
                  const [],
              // Watched rather than read once: the dialog can be open while
              // a roster poll lands, and a picker showing a region as idle
              // while a call fills it is worse than showing nothing.
              load: context.watch<ServerCubit>().state.regionLoad,
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
    );
  }
}
