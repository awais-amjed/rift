import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../theme/app_motion.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// What a chat pane says while files are dragged over it.
///
/// Never hit-tested: the drag is the platform's, not a Flutter pointer, and a
/// card that took pointers would swallow the hover on the pane underneath the
/// moment the drag left.
class ChatDropOverlay extends StatelessWidget {
  final bool visible;

  const ChatDropOverlay({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: AppMotion.react,
        curve: AppMotion.settle,
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.bgContent.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(color: theme.primary, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attach_file_rounded, size: 32, color: theme.primary),
              const SizedBox(height: 10),
              Text(
                'Drop to attach',
                style: AppText.sectionTitle.copyWith(color: theme.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
