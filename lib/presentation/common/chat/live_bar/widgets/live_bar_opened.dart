import 'package:flutter/material.dart';

import '../../../../theme/app_motion.dart';
import '../../../../theme/theme_context.dart';

/// What an opened line of the live bar shows under its top row, grown into
/// rather than snapped in, and scrolling inside itself past [maxHeight] so the
/// bar never covers the conversation.
class LiveBarOpened extends StatelessWidget {
  final bool open;
  final double maxHeight;
  final Widget child;

  const LiveBarOpened({
    super.key,
    required this.open,
    required this.maxHeight,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AnimatedSize(
      duration: AppMotion.state,
      curve: AppMotion.settle,
      alignment: Alignment.topCenter,
      child: open
          ? ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: theme.borderPrimary)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: child,
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
