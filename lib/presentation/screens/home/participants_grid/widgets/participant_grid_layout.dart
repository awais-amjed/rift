import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../data/participant_identity.dart';
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
  String? _expandedParticipantIdentity;

  Widget _buildTile(Participant p) {
    final setting =
        widget.participantSettings[ParticipantIdentity.userIdOf(p.identity)];
    final isMuted = (setting as dynamic)?.muted ?? false;
    return ParticipantTileWidget(
      participant: p,
      isMuted: isMuted,
      onTap: () => _onTileTapped(p.identity),
    );
  }

  void _onTileTapped(String identity) {
    setState(() {
      if (_expandedParticipantIdentity == identity) {
        // Collapse if already expanded
        _expandedParticipantIdentity = null;
      } else {
        // Expand this tile
        _expandedParticipantIdentity = identity;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // If a tile is expanded, show only that tile in full view
    if (_expandedParticipantIdentity != null) {
      final expandedParticipant = widget.participants.firstWhere(
        (p) => p.identity == _expandedParticipantIdentity,
        orElse: () {
          // If participant no longer exists, reset expanded state
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _expandedParticipantIdentity = null;
            });
          });
          return widget.participants.first;
        },
      );

      final setting =
          widget.participantSettings[ParticipantIdentity.userIdOf(
            expandedParticipant.identity,
          )];
      final isMuted = (setting as dynamic)?.muted ?? false;

      return ParticipantTileWidget(
        participant: expandedParticipant,
        isMuted: isMuted,
        onTap: () => _onTileTapped(expandedParticipant.identity),
        isExpanded: true,
      );
    }

    // Screenshares get a hero layout: the share fills most of the width and
    // camera tiles collapse into a scrollable rail on the right.
    final shares = widget.participants
        .where((p) => ParticipantIdentity.isScreenshare(p.identity))
        .toList();
    if (shares.isNotEmpty && widget.participants.length > shares.length) {
      final cameras = widget.participants
          .where((p) => !ParticipantIdentity.isScreenshare(p.identity))
          .toList();
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  for (var i = 0; i < shares.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Expanded(child: _buildTile(shares[i])),
                  ],
                ],
              ),
            ),
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

    // Compute grid columns based on participant count
    int cols = 1;
    if (widget.participants.length >= 2) cols = 2;
    if (widget.participants.length >= 5) cols = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate max width regarding the aspect ratio to ensure the grid fits vertically
        final int rows = (widget.participants.length / cols).ceil();
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
              itemCount: widget.participants.length,
              itemBuilder: (context, index) {
                final p = widget.participants[index];
                final setting =
                    widget.participantSettings[ParticipantIdentity.userIdOf(
                      p.identity,
                    )];
                final isMuted = (setting as dynamic)?.muted ?? false;
                return ParticipantTileWidget(
                  participant: p,
                  isMuted: isMuted,
                  onTap: () => _onTileTapped(p.identity),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
