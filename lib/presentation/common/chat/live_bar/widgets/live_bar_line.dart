import 'package:flutter/material.dart';

import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One folded row of the live bar: an icon, what it is about, a quieter word
/// or two after it, and the chevron that says it opens.
///
/// The whole row is the tap target. Opened, the same row is what folds it
/// again — the only way besides Escape, so a vote in a multiple-choice poll
/// never folds it out from under the reader.
class LiveBarLine extends StatelessWidget {
  final IconData icon;
  final String title;

  /// After the title, in the quiet colour: "4 votes · 2h left".
  final String? meta;

  /// At the far end, in the accent: "+2 more".
  final String? trailing;

  final bool open;
  final VoidCallback onTap;

  const LiveBarLine({
    super.key,
    required this.icon,
    required this.title,
    this.meta,
    this.trailing,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
          child: Row(
            spacing: 8,
            children: [
              Icon(icon, size: 16, color: theme.accentBright),
              // The title gives way, the short meta after it does not.
              Expanded(
                child: Row(
                  spacing: 6,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.strong.copyWith(
                          color: theme.textPrimary,
                        ),
                      ),
                    ),
                    if (meta != null)
                      Text(
                        meta!,
                        maxLines: 1,
                        style: AppText.meta.copyWith(color: theme.textTertiary),
                      ),
                  ],
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  maxLines: 1,
                  style: AppText.meta.copyWith(
                    color: theme.accentBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Icon(
                open ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                size: 18,
                color: theme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
