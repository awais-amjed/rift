import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../participant_tile.dart';

/// Grid view displaying all participants with adaptive column count.
class ParticipantGrid extends StatelessWidget {
  final List<Participant> participants;
  final Map<String, dynamic> participantSettings;

  const ParticipantGrid({
    super.key,
    required this.participants,
    required this.participantSettings,
  });

  @override
  Widget build(BuildContext context) {
    // Compute grid columns based on participant count
    int cols = 1;
    if (participants.length >= 2) cols = 2;
    if (participants.length >= 5) cols = 3;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate max width regarding the aspect ratio to ensure the grid fits vertically
        final int rows = (participants.length / cols).ceil();
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
              itemCount: participants.length,
              itemBuilder: (context, index) {
                final p = participants[index];
                final setting = participantSettings[p.identity];
                final isMuted = (setting as dynamic)?.muted ?? false;
                return ParticipantTileWidget(participant: p, isMuted: isMuted);
              },
            ),
          ),
        );
      },
    );
  }
}
