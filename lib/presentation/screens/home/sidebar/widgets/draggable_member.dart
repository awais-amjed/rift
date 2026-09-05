import 'package:flutter/material.dart';

import '../../../../../data/classes/voice_drag.dart';
import '../../../../../data/constants.dart';
import '../../../../common/squircle_avatar.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Makes a voice-channel row something you can pick up and drop on another
/// channel, which is the direct way to say what the "Move to" submenu says.
///
/// Off unless [enabled] — staff can drag anyone, and anyone can drag
/// themselves. A row that can't go anywhere shouldn't lift under the pointer.
///
/// A long press starts the drag on touch, a press-and-move on a mouse; both
/// come from [Draggable], and neither takes the right-click that opens the
/// row's context menu.
class DraggableMember extends StatelessWidget {
  final VoiceDrag member;
  final bool enabled;
  final Widget child;

  const DraggableMember({
    super.key,
    required this.member,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    // Read here rather than inside the chip: the feedback is built in the
    // overlay, which is outside this tree, so it can't look a cubit up for
    // itself — the same reason a context menu is handed its cubits.

    return Draggable<VoiceDrag>(
      data: member,
      // The chip follows the pointer rather than keeping the grab offset: it's
      // much smaller than the row it came from, so holding the original offset
      // would leave it floating away from the cursor.
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _Chip(member: member),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }
}

/// What travels with the pointer: avatar and name, small enough to see the
/// channel underneath it.
class _Chip extends StatelessWidget {
  final VoiceDrag member;
  const _Chip({required this.member});

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Material(
      color: Colors.transparent,
      child: Padding(
        // Lifts the chip clear of the cursor so it doesn't cover the drop.
        padding: const EdgeInsets.only(left: 10, top: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: themeState.bgElevated,
            borderRadius: BorderRadius.circular(K.radiusRow),
            border: Border.all(color: themeState.accentBright),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              SquircleAvatar(name: member.name, seed: member.userId, size: 20),
              Text(
                member.name,
                style: AppText.row.copyWith(color: themeState.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
