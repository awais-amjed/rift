import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';
import 'voice_region_row.dart';

/// The LiveKit nodes this server may hold calls on.
///
/// Acts immediately rather than on Save, like the push toggle on Overview and
/// for the same reason: adding a region is a row of its own, not a field on
/// the server, and half-applying it would leave a channel pinned to something
/// that was never created.
///
/// **A call still lives on exactly one node.** Adding regions does not spread
/// one call across them — it gives a call a better choice of where to be. The
/// helper line says so, because "regions" in a voice product usually promises
/// the thing LiveKit's open-source server cannot do.
///
/// **Only the server you are looking at can be changed here**, and the list is
/// read from [serverId] rather than from the selection so that the rest of the
/// time it at least shows the right regions. Every write below goes through
/// the selected server — adding a region ends by re-reading that server's
/// details, which is what puts the new row and every channel's pin back in
/// step — so pointing this at another server would edit the wrong one and then
/// refresh neither. Said in a note rather than by hiding the page: an operator
/// opening Voice from the rail's menu is owed the reason it is flat.
class ServerVoiceRegionsSection extends StatefulWidget {
  final String serverId;
  final bool enabled;

  const ServerVoiceRegionsSection({
    super.key,
    required this.serverId,
    this.enabled = true,
  });

  @override
  State<ServerVoiceRegionsSection> createState() =>
      _ServerVoiceRegionsSectionState();
}

class _ServerVoiceRegionsSectionState extends State<ServerVoiceRegionsSection> {
  final _labelCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  /// Whether this is the server the app is actually on — see the class note.
  bool get _isSelected =>
      context.read<ServerCubit>().state.selectedServer?.id == widget.serverId;

  bool get _canAdd =>
      !_busy &&
      widget.enabled &&
      _labelCtrl.text.trim().isNotEmpty &&
      _urlCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<({bool success, String? error})> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result.success ? null : result.error;
    });
  }

  Future<void> _add() async {
    if (!_canAdd) return;
    final label = _labelCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    await _run(
      () => context.read<ServerCubit>().addVoiceRegion(label: label, url: url),
    );
    if (!mounted || _error != null) return;
    _labelCtrl.clear();
    _urlCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final nodes = context.select<ServerCubit, List<LiveKitNode>>(
      (c) => c.state.serverById(widget.serverId)?.livekitNodes ?? const [],
    );
    final changeable = widget.enabled && !_busy && _isSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Regions'),
        const SizedBox(height: 6),
        Text(
          'Extra LiveKit servers, so a call can be held near the people in '
          'it. A call runs on one region — whichever it was started in — so '
          'this chooses where, not how many. Click a name or an address to '
          'change it — the first region\'s address is the LiveKit URL above.',
          style: AppText.secondary.copyWith(color: theme.textQuaternary),
        ),
        if (!_isSelected) ...[
          const SizedBox(height: 12),
          const HintCard(
            icon: Icons.swap_horiz_rounded,
            text:
                'Open this server in the rail to change its regions. The '
                'LiveKit fields above save from here either way.',
          ),
        ],
        const SizedBox(height: 14),
        for (final node in nodes) ...[
          VoiceRegionRow(
            node: node,
            enabled: changeable,
            onRemove: () => _run(
              () => context.read<ServerCubit>().deleteVoiceRegion(node.id),
            ),
            onRename: (label) => _run(
              () => context.read<ServerCubit>().updateVoiceRegion(
                nodeId: node.id,
                label: label,
              ),
            ),
            onRetarget: (url) => _run(
              () => context.read<ServerCubit>().updateVoiceRegion(
                nodeId: node.id,
                url: url,
              ),
            ),
            // Refused before it was sent, so there is nothing to await —
            // just the sentence, in the same place a server error lands.
            onInvalid: (message) => setState(() => _error = message),
          ),
          const SizedBox(height: 8),
        ],
        if (_isSelected) ...[
          const SizedBox(height: 6),
          AppTextField(
            controller: _labelCtrl,
            label: 'Region name',
            hint: 'Singapore',
            enabled: widget.enabled && !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _urlCtrl,
            label: 'LiveKit URL',
            hint: 'wss://sg.example.com',
            enabled: widget.enabled && !_busy,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 6),
          Text(
            'Give it the same API key and secret as the LiveKit above — every '
            'region signs with the one pair.',
            style: AppText.secondary.copyWith(color: theme.textQuaternary),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: AppText.secondary.copyWith(color: theme.textTertiary),
          ),
        ],
        if (_isSelected) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add region',
              variant: AppButtonVariant.secondary,
              isLoading: _busy,
              onPressed: _canAdd ? _add : null,
            ),
          ),
        ],
      ],
    );
  }
}
