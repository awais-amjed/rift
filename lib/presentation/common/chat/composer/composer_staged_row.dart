import 'package:flutter/material.dart';

import '../../../../data/classes/pending_attachment.dart';
import '../../../../data/constants.dart';
import 'composer_staged_chip.dart';

/// The horizontal strip of staged-attachment chips shown above the input.
class ComposerStagedRow extends StatelessWidget {
  static const double _height = 76;

  final List<PendingAttachment> staged;
  final ValueChanged<int> onRemove;

  /// Switches a big file to unencrypted and back. Null where that is not
  /// offered.
  final ValueChanged<int>? onTogglePlain;

  const ComposerStagedRow({
    super.key,
    required this.staged,
    required this.onRemove,
    this.onTogglePlain,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: _height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: staged.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ComposerStagedChip(
          attachment: staged[i],
          onRemove: () => onRemove(i),
          onTogglePlain:
              onTogglePlain != null &&
                  staged[i].size >= K.plainAttachmentMinBytes
              ? () => onTogglePlain!(i)
              : null,
        ),
      ),
    );
  }
}
