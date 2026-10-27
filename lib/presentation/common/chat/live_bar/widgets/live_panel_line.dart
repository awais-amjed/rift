import 'package:flutter/material.dart';

import '../../../../../data/classes/panel_block.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/services/attachment_loader.dart';
import '../../../../../logic/services/panel_summary.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../attachments/attachment_image_thumb.dart';

/// A bot's live panel folded to one line: its cover, what it is playing, a
/// couple of its buttons usable without opening it, and its progress as a
/// thin line along the bottom edge. Read out of the blocks ([PanelSummary]).
///
/// The row opens the whole panel; the buttons press their action and leave
/// it as it is. Opened, the line drops them for the panel's full row, which
/// the bar keeps in sight.
class LivePanelLine extends StatelessWidget {
  final PanelSummary summary;

  /// Who drew it, after the second line: "Aphex Twin · DJ Riff".
  final String botName;

  final bool open;
  final VoidCallback onTap;

  /// Null where the reader cannot press — the buttons are then drawn dimmed.
  final void Function(String action, String? value)? onAction;

  /// Without one the cover is left out, as [PanelView] leaves out an image.
  final AttachmentLoader? loader;

  /// The cover's side.
  static const double coverSize = 34;

  const LivePanelLine({
    super.key,
    required this.summary,
    required this.botName,
    required this.open,
    required this.onTap,
    required this.onAction,
    required this.loader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final cover = summary.cover?.image;
    final loader = this.loader;
    final second = [?summary.subtitle, botName].join(' · ');
    final progress = summary.progress;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
              child: Row(
                spacing: 8,
                children: [
                  if (cover != null && loader != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(K.radiusRow),
                      child: SizedBox.square(
                        dimension: coverSize,
                        // The chat's own picture, scaled down whole: sized
                        // from its digest-checked bytes and covered by the
                        // sensitive-image setting, as it is in the panel.
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: AttachmentImageThumb(
                            key: ValueKey(cover.attachment.id),
                            attachment: cover.attachment,
                            loader: loader,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          summary.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.strong.copyWith(
                            color: theme.textPrimary,
                          ),
                        ),
                        Text(
                          second,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.meta.copyWith(
                            color: theme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Open, the panel's own row is right below.
                  if (!open)
                    for (final button in summary.buttons)
                      _LineButton(
                        action: button,
                        onTap: onAction == null
                            ? null
                            : () => onAction!(button.action, button.value),
                      ),
                  Icon(
                    open
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 18,
                    color: theme.textTertiary,
                  ),
                ],
              ),
            ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation(theme.primary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One of the panel's buttons, small enough to sit on the folded line.
class _LineButton extends StatelessWidget {
  final PanelAction action;
  final VoidCallback? onTap;

  const _LineButton({required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            child: Text(
              action.label,
              maxLines: 1,
              style: AppText.chip.copyWith(
                color: action.style == PanelButtonStyle.primary
                    ? theme.accentBright
                    : theme.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
