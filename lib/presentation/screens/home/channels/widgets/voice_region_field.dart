import 'package:flutter/material.dart';

import '../../../../../data/classes/livekit_node.dart';
import '../../../../../data/classes/region_load.dart';
import '../../../../../data/constants.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';

/// Which LiveKit a voice channel's calls are held on.
///
/// **Shown even when a server has only one node**, where it can change
/// nothing. It is the only place in Rift that says where a call actually
/// runs, and a manager wanting to know that should not have to add a second
/// node to find out. So the automatic entry names the node it resolves to —
/// "Automatic (Frankfurt)" — which reads as information at one node and as a
/// decision at three, from the same widget.
///
/// **A channel setting, not a member's.** Everybody in a call shares one room
/// on one node, so a member who could choose would be choosing a different
/// call.
///
/// A room cannot migrate, so a call that is already up does not follow this
/// setting on its own — moving one means everybody in it reconnecting, and
/// that costs the room a second or two of silence. Saving a different region
/// while a call is running is what asks for it, and [liveNodeId] is how the
/// helper line says so before the button is pressed rather than after.
class VoiceRegionField extends StatelessWidget {
  /// Every node this server may hold a call on, default first.
  final List<LiveKitNode> nodes;

  /// How busy each is, keyed by node id — empty until the first roster poll.
  ///
  /// Shown beside each region because the question a manager has when they
  /// open this is usually "the calls here are bad, where else could they
  /// go", and a list of names alone cannot answer it.
  final Map<String, RegionLoad> load;

  /// The channel's pin, or null for automatic.
  final String? selectedNodeId;

  /// Where a call on this channel is right now, if there is one.
  final String? liveNodeId;

  final bool enabled;

  /// Null means automatic.
  final ValueChanged<String?> onChanged;

  const VoiceRegionField({
    super.key,
    required this.nodes,
    required this.selectedNodeId,
    required this.liveNodeId,
    required this.onChanged,
    this.load = const {},
    this.enabled = true,
  });

  /// What "Automatic" would land on if a call opened now: wherever one
  /// already is, else the default node. It cannot promise more than that —
  /// with several nodes and nobody in the call, the answer is whichever the
  /// first person to join measures as nearest, which is not knowable here.
  LiveKitNode? get _automaticResolvesTo {
    if (nodes.isEmpty) return null;
    final live = _nodeById(liveNodeId);
    if (live != null) return live;
    if (nodes.length > 1) return null;
    return nodes.firstWhere((n) => n.isDefault, orElse: () => nodes.first);
  }

  LiveKitNode? _nodeById(String? id) {
    if (id == null) return null;
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  String get _automaticLabel {
    final resolved = _automaticResolvesTo;
    return resolved == null ? 'Automatic' : 'Automatic (${resolved.label})';
  }

  /// The line under the field. It answers the question a manager actually has
  /// — where is this call — before the one the control asks.
  String _helper() {
    final live = _nodeById(liveNodeId);
    if (live != null) {
      final pinned = _nodeById(selectedNodeId);
      if (pinned != null && pinned.id != live.id) {
        return 'A call is running in ${live.label}. Saving moves it to '
            '${pinned.label} — everyone in it reconnects, which takes a '
            'moment.';
      }
      return 'A call is running in ${live.label}.';
    }
    if (selectedNodeId != null) {
      return 'Calls here are always held in this region.';
    }
    if (nodes.length <= 1) {
      return 'This server has one voice region.';
    }
    return 'Rift picks the region closest to whoever starts the call. '
        'Everyone who joins connects there.';
  }

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Region',
          style: AppText.label.copyWith(color: theme.textSecondary),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String?>(
          initialValue: selectedNodeId,
          isExpanded: true,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(K.radiusRow),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(_automaticLabel, overflow: TextOverflow.ellipsis),
            ),
            for (final node in nodes)
              DropdownMenuItem<String?>(
                value: node.id,
                child: _RegionLine(node: node, load: load[node.id]),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
        const SizedBox(height: 5),
        Text(
          _helper(),
          style: AppText.secondary.copyWith(color: theme.textQuaternary),
        ),
      ],
    );
  }
}

/// A region's name with what it is carrying, for one row of the picker.
///
/// The load is a whisper rather than a badge: it is context for a decision,
/// not a warning, and a row that shouted would make every region look like a
/// problem. A region that is *offline* is the exception — that one is
/// worth seeing.
class _RegionLine extends StatelessWidget {
  final LiveKitNode node;
  final RegionLoad? load;

  const _RegionLine({required this.node, this.load});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final summary = load?.summary;

    return Row(
      children: [
        Flexible(child: Text(node.label, overflow: TextOverflow.ellipsis)),
        if (summary != null) ...[
          const SizedBox(width: 8),
          Text(
            summary,
            style: AppText.secondary.copyWith(
              color: load!.reachable
                  ? theme.textQuaternary
                  : theme.statusInk(CustomColors.warning),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
