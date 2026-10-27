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

  /// Drawn under [child] and never scrolled with it: a panel's own buttons,
  /// which a tall cover otherwise pushed out of sight.
  final Widget? footer;

  const LiveBarOpened({
    super.key,
    required this.open,
    required this.maxHeight,
    required this.child,
    this.footer,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          4,
                          12,
                          footer == null ? 12 : 4,
                        ),
                        child: child,
                      ),
                    ),
                    if (footer case final footer?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: footer,
                      ),
                  ],
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}
