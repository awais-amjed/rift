import 'package:flutter/material.dart';

import '../../../../data/classes/forwarded_message.dart';
import '../../../../data/constants.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../message_markup_text.dart';
import '../attachments/attachment_loader.dart';
import '../attachments/message_attachments.dart';

/// Words somebody carried in from another conversation.
///
/// **It says "Forwarded" and no more** — not who wrote it and not where it
/// came from. Naming the room would tell readers who were never in it that
/// a place exists they cannot see, which on a private server is the whole
/// of what there was to keep; and the author could only ever have been a
/// claim, because the original signature does not survive the re-sealing.
/// See [ForwardedMessage].
///
/// The row around this carries the forwarder's avatar, name and time,
/// because they are what the signature on *this* message attests. The card
/// is subordinate by construction — a rule down its left edge, a quieter
/// ground, the label at label size — so it never borrows the header
/// treatment a real message gets.
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
            const _ForwardedLabel(),
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

/// The one word the card carries about where this came from.
class _ForwardedLabel extends StatelessWidget {
  const _ForwardedLabel();

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Row(
      children: [
        Icon(
          Icons.forward_rounded,
          size: K.iconInline,
          color: theme.textTertiary,
        ),
        const SizedBox(width: 6),
        Text(
          'Forwarded',
          style: AppText.chip.copyWith(color: theme.textTertiary),
        ),
      ],
    );
  }
}
