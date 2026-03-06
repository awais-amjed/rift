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

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 16 / 9,
      ),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final p = participants[index];
        final setting = participantSettings[p.identity];
        final isMuted = (setting as dynamic)?.muted ?? false;
        return ParticipantTileWidget(participant: p, isMuted: isMuted);
      },
    );
  }
}
