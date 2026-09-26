import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/livekit_node.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/confirm_dialog.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';
import 'voice_region_dialog.dart';
import 'voice_region_row.dart';

/// The LiveKit nodes this server may hold calls on — the top of the Regions
/// page, and the first region in the list is the server's own LiveKit.
///
/// Every change acts immediately rather than on a Save, because each one is a
/// row of its own rather than a field on the server: half-applying an added
/// region would leave a channel pinned to something that was never created.
/// The dialogs are where the waiting and the cancelling happen, so the list
/// itself only ever shows what is really there.
///
/// **A call still lives on exactly one node.** Adding regions does not spread
/// one call across them — it gives a call a better choice of where to be. The
/// helper line says so, because "regions" in a voice product usually promises
/// the thing LiveKit's open-source server cannot do.
///
/// **Only the server you are looking at can be changed here**, and the list is
/// read from [serverId] rather than from the selection so that the rest of the
/// time it at least shows the right regions. Every write below goes through
/// the selected server — each one ends by re-reading that server's details,
/// which is what puts the new row and every channel's pin back in step — so
/// pointing this at another server would edit the wrong one and then refresh
/// neither. Said in a note rather than by hiding the page: an operator opening
/// Regions from the rail's menu is owed the reason it is flat.
class VoiceRegionsSection extends StatefulWidget {
  final String serverId;
  final bool enabled;

  const VoiceRegionsSection({
    super.key,
    required this.serverId,
    this.enabled = true,
  });

  @override
  State<VoiceRegionsSection> createState() => _VoiceRegionsSectionState();
}

class _VoiceRegionsSectionState extends State<VoiceRegionsSection> {
  bool _busy = false;

  /// Whether this is the server the app is actually on — see the class note.
  bool get _isSelected =>
      context.read<ServerCubit>().state.selectedServer?.id == widget.serverId;

  /// Asks first, and says what it is about to take away.
  ///
  /// A channel pinned to this region is not blocked from losing it — the
  /// column is `ON DELETE SET NULL` and such a channel falls back to
  /// automatic — but somebody who chose that pin deserves to hear about it
  /// before the row goes.
  Future<void> _remove(LiveKitNode node) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove region',
      message:
          '${node.label} will no longer hold calls. Any channel set to it '
          'goes back to picking a region automatically, and a call already '
          'running there stays up until everyone leaves.',
      confirmLabel: 'Remove region',
      icon: Icons.delete_outline_rounded,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final result = await context.read<ServerCubit>().deleteVoiceRegion(node.id);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.success) {
      HelperMethods.showSuccess(message: 'Region removed');
    } else {
      HelperMethods.showError(
        error: result.error ?? 'Failed to remove the region',
      );
    }
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
        Text(
          'Add a region for each place you run a LiveKit server, so calls '
          'can be held near the people in them. A whole call runs in one '
          'region, and everyone who joins connects there. The default region '
          'can\'t be removed.',
          style: AppText.secondary.copyWith(color: theme.textQuaternary),
        ),
        if (!_isSelected) ...[
          const SizedBox(height: 12),
          const HintCard(
            icon: Icons.swap_horiz_rounded,
            text: 'Switch to this server to change its regions.',
          ),
        ],
        const SizedBox(height: 14),
        for (final node in nodes) ...[
          VoiceRegionRow(
            node: node,
            enabled: changeable,
            onEdit: () => showVoiceRegionDialog(context, node: node),
            onRemove: node.isDefault ? null : () => _remove(node),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
