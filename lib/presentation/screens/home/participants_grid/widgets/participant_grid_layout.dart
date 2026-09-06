import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../data/participant_identity.dart';
import '../../../../../logic/services/room_tiles.dart';
import '../../../../../logic/services/voice_tiles.dart';
import '../../../../responsive/shell_scope.dart';
import '../participants_tile/participant_tile.dart';

/// Grid view displaying all participants with adaptive column count.
class ParticipantGridLayout extends StatefulWidget {
  final List<Participant> participants;
  final Map<String, dynamic> participantSettings;

  const ParticipantGridLayout({
    super.key,
    required this.participants,
    required this.participantSettings,
  });

  @override
  State<ParticipantGridLayout> createState() => _ParticipantGridLayoutState();
}

class _ParticipantGridLayoutState extends State<ParticipantGridLayout> {
  /// Which cell is expanded, by [_keyOf] rather than by identity — one person
  /// sharing from a phone owns two cells under the same identity, and an
  /// identity alone cannot say which of them was tapped.
  String? _expandedKey;

  static String _keyOf(VoiceTile<Participant> tile) =>
      '${tile.participant.identity}${tile.isScreenshare ? '#share' : ''}';

  /// The cells to draw. A share is a cell, not a participant — see
  /// [voiceTilesFor].
  List<VoiceTile<Participant>> get _tiles =>
      roomVoiceTiles(widget.participants);

  Widget _buildTile(VoiceTile<Participant> tile) {
    final setting =
        widget.participantSettings[ParticipantIdentity.userIdOf(
          tile.participant.identity,
        )];
    final isMuted = (setting as dynamic)?.muted ?? false;
    return ParticipantTileWidget(
      participant: tile.participant,
      isScreenshare: tile.isScreenshare,
      isMuted: isMuted,
      onTap: () => _onTileTapped(_keyOf(tile)),
    );
  }

  void _onTileTapped(String key) {
    setState(() {
      // Collapse if already expanded, otherwise expand this one.
      _expandedKey = _expandedKey == key ? null : key;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tiles = _tiles;

    // If a tile is expanded, show only that tile in full view
    if (_expandedKey != null) {
      final expanded = tiles
          .where((t) => _keyOf(t) == _expandedKey)
          .firstOrNull;
      if (expanded == null) {
        // The cell went away — the sharer stopped, or the participant left.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _expandedKey = null);
        });
      } else {
        final setting =
            widget.participantSettings[ParticipantIdentity.userIdOf(
              expanded.participant.identity,
            )];
        final isMuted = (setting as dynamic)?.muted ?? false;

        return ParticipantTileWidget(
          participant: expanded.participant,
          isScreenshare: expanded.isScreenshare,
          isMuted: isMuted,
          onTap: () => _onTileTapped(_keyOf(expanded)),
          isExpanded: true,
        );
      }
    }

    // Screenshares get a hero layout: the share fills most of the width and
    // camera tiles collapse into a scrollable rail on the right.
    final shares = tiles.where((t) => t.isScreenshare).toList();
    final cameras = tiles.where((t) => !t.isScreenshare).toList();
    if (shares.isNotEmpty && cameras.isNotEmpty) {
      final shareStack = Column(
        children: [
          for (var i = 0; i < shares.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Expanded(child: _buildTile(shares[i])),
          ],
        ],
      );

      // A phone is tall and narrow, so the rail goes underneath rather than
      // beside: a quarter of a 390px screen is not a camera tile, it is a
      // sliver, and it would take that quarter away from the thing everyone
      // is actually looking at.
      if (context.layoutMode.isCompact) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: shareStack),
              const SizedBox(height: 8),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cameras.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _buildTile(cameras[index]),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 4, child: shareStack),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ListView.separated(
                itemCount: cameras.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildTile(cameras[index]),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Compute grid columns based on how many cells there are
    int cols = 1;
    if (tiles.length >= 2) cols = 2;
    if (tiles.length >= 5) cols = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate max width regarding the aspect ratio to ensure the grid fits vertically
        final int rows = (tiles.length / cols).ceil();
        const double gridPadding = 12.0;
        const double gridSpacing = 8.0;

        // Available height excludes vertical padding
        final double availableHeight =
            constraints.maxHeight - (gridPadding * 2);

        // Height taken by spacing between rows
        final double spacingHeight = (rows > 1) ? (rows - 1) * gridSpacing : 0;

        // Remaining height for participant tiles
        final double heightForTiles = availableHeight - spacingHeight;

        double maxWidthConstraint = double.infinity;

        if (heightForTiles > 0 && rows > 0 && constraints.maxHeight.isFinite) {
          final double maxTileHeight = heightForTiles / rows;
          final double maxTileWidth = maxTileHeight * (16 / 9);

          final double spacingWidth = (cols > 1) ? (cols - 1) * gridSpacing : 0;
          final double contentWidth = (maxTileWidth * cols) + spacingWidth;

          maxWidthConstraint = contentWidth + (gridPadding * 2);
        }

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidthConstraint),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(gridPadding),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: gridSpacing,
                mainAxisSpacing: gridSpacing,
                childAspectRatio: 16 / 9,
              ),
              itemCount: tiles.length,
              itemBuilder: (context, index) => _buildTile(tiles[index]),
            ),
          ),
        );
      },
    );
  }
}
