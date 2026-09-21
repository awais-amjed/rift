import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/services/screen_share_sources.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// One application that is playing something, as a row you can pick.
///
/// Two lines, because both matter and neither is enough on its own: the
/// application, which is what you think of yourself as sharing, and what it is
/// playing, which is how you tell two browser tabs apart.
class AudioSourceRow extends StatelessWidget {
  final AudioSource source;
  final bool selected;
  final VoidCallback onTap;

  const AudioSourceRow({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  /// The application's own name, and something rather than an empty row when
  /// it offered none.
  static String titleOf(AudioSource source) {
    final label = ScreenShareSources.appLabel(source);
    return label.isEmpty ? 'Unknown application' : label;
  }

  /// What it is playing right now, when it says — a track, a video, a tab.
  static String? subtitleOf(AudioSource source) {
    final media = source.mediaName.trim();
    return media.isEmpty || media == titleOf(source) ? null : media;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final subtitle = subtitleOf(source);
    final radius = BorderRadius.circular(K.radiusRow);

    return Material(
      color: selected
          ? theme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? theme.primary : theme.borderPrimary,
            ),
          ),
          child: Row(
            spacing: 12,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 18,
                color: selected ? theme.primary : theme.textTertiary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleOf(source),
                      style: AppText.row.copyWith(color: theme.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: AppText.secondary.copyWith(
                          color: theme.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, size: 18, color: theme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
