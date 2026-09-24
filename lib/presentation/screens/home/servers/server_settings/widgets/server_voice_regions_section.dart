import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/app_text_field.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import '../../../../settings/widgets/section_title.dart';
import 'voice_region_row.dart';

/// The LiveKit nodes this server may hold calls on.
///
/// Acts immediately rather than on Save, like the push toggle above it and
/// for the same reason: adding a region is a row of its own, not a field on
/// the server, and half-applying it would leave a channel pinned to something
/// that was never created.
///
/// **A call still lives on exactly one node.** Adding regions does not spread
/// one call across them — it gives a call a better choice of where to be. The
/// helper line says so, because "regions" in a voice product usually promises
/// the thing LiveKit's open-source server cannot do.
class ServerVoiceRegionsSection extends StatefulWidget {
  final bool enabled;

  const ServerVoiceRegionsSection({super.key, this.enabled = true});

  @override
  State<ServerVoiceRegionsSection> createState() =>
      _ServerVoiceRegionsSectionState();
}

class _ServerVoiceRegionsSectionState extends State<ServerVoiceRegionsSection> {
  final _labelCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

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
      (c) => c.state.selectedServer?.livekitNodes ?? const [],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionTitle(label: 'Voice regions'),
        const SizedBox(height: 6),
        Text(
          'Extra LiveKit servers, so a call can be held near the people in '
          'it. A call runs on one region — whichever it was started in — so '
          'this chooses where, not how many.',
          style: AppText.secondary.copyWith(color: theme.textQuaternary),
        ),
        const SizedBox(height: 14),
        for (final node in nodes) ...[
          VoiceRegionRow(
            node: node,
            enabled: widget.enabled && !_busy,
            onRemove: () => _run(
              () => context.read<ServerCubit>().deleteVoiceRegion(node.id),
            ),
          ),
          const SizedBox(height: 8),
        ],
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
          'Give it the same API key and secret as the server above — every '
          'region signs with the one pair.',
          style: AppText.secondary.copyWith(color: theme.textQuaternary),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: AppText.secondary.copyWith(color: theme.textTertiary),
          ),
        ],
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
    );
  }
}
