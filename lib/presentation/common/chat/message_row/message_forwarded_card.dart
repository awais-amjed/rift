import 'package:flutter/material.dart';

import '../../../../data/classes/forwarded_message.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../message_markup_text.dart';
import '../attachments/attachment_loader.dart';
import '../attachments/message_attachments.dart';

/// A message somebody carried in from another conversation.
///
/// **Drawn as a quotation inside the forwarder's row, never as the original
/// author posting here**, and the whole widget exists to keep that
/// distinction visible. The row above it carries the forwarder's avatar,
/// name and time, because they are what the signature on this message
/// attests. Everything inside this card — the name, the time, the words —
/// is what they say was written elsewhere, and a reader here has no way to
/// check it, exactly as with a screenshot.
///
/// So the card is subordinate by construction: a rule down its left edge, a
/// quieter ground, the attribution at label size. It never borrows the
/// header treatment a real message gets, because looking like one is the
/// only failure that matters here.
class MessageForwardedCard extends StatelessWidget {
  final ForwardedMessage forwarded;

  /// Fetches the re-uploaded blobs, which live in *this* conversation's
  /// scope — the bytes were copied on the way in, so the ordinary loader
  /// for this surface is the right one.
  final AttachmentLoader? attachmentLoader;

  const MessageForwardedCard({
    super.key,
    required this.forwarded,
    this.attachmentLoader,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final loader = attachmentLoader;

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
        decoration: BoxDecoration(
          color: theme.bgTertiary,
          borderRadius: BorderRadius.circular(K.radiusRow),
          border: Border(
            left: BorderSide(color: theme.borderElevated, width: 2),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _Attribution(forwarded: forwarded),
            if (forwarded.text.isNotEmpty) ...[
              const SizedBox(height: 4),
              // The same markup the surrounding conversation uses, with no
              // mentions passed: an `@name` inside a forward is a name from
              // somewhere else, and lighting it up here would promise a ping
              // that was never sent to anybody in this room.
              Text.rich(
                messageMarkupSpan(
                  forwarded.text,
                  base: AppText.body.copyWith(color: theme.textSecondary),
                  theme: theme,
                ),
              ),
            ],
            if (loader != null && forwarded.attachments.isNotEmpty)
              MessageAttachments(
                attachments: forwarded.attachments,
                loader: loader,
              ),
          ],
        ),
      ),
    );
  }
}

/// Who the forwarder says wrote it, and where. Label size and tertiary, so
/// it reads as a citation rather than as a byline.
class _Attribution extends StatelessWidget {
  final ForwardedMessage forwarded;

  const _Attribution({required this.forwarded});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final source = forwarded.source;
    return Row(
      children: [
        Icon(Icons.forward_rounded, size: 13, color: theme.textTertiary),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Forwarded from ',
                  style: AppText.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: theme.textTertiary,
                  ),
                ),
                TextSpan(
                  text: forwarded.authorName,
                  style: AppText.chip.copyWith(color: theme.textSecondary),
                ),
                if (source != null)
                  TextSpan(
                    text: ' · $source',
                    style: AppText.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: theme.textTertiary,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
