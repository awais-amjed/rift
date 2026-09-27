import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/theme_context.dart';
import '../participants_grid/participants_grid.dart';

/// A DM conversation's call, above its messages, on a desktop.
///
/// Above rather than instead of: the conversation is where the two of you
/// already were, and a link or a screenshot passed mid-call lands in it. The
/// stage takes a share of the pane rather than a fixed height, so a tall
/// window gets a bigger picture and a short one keeps its messages readable.
class DmCallStage extends StatelessWidget {
  /// The pane's height, which the share is taken of.
  final double available;

  const DmCallStage({super.key, required this.available});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final height = math.max(K.dmCallStageMin, available * K.dmCallStageShare);
    return Container(
      height: math.min(height, available),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.borderPrimary)),
      ),
      child: const ParticipantsGrid(embedded: true),
    );
  }
}
