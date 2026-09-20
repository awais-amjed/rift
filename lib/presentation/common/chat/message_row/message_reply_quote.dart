import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/message_excerpt.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The line above a reply saying what it answers.
///
/// [original] is the message this client has already decrypted and verified,
/// or null when the reference points at something it cannot show — deleted,
/// still locked, or simply older than the loaded page. **Null renders as an
/// admission, never as the sender's account of what was there**: the body
/// carries an id and no text precisely so a replier cannot put words in
/// somebody else's mouth, and inventing a quote here would hand that back.
class MessageReplyQuote extends StatelessWidget {
  final ChatMessage? original;

  const MessageReplyQuote({super.key, this.original});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final message = original;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The elbow: a short stub rising into the row above. It does the
          // work an indent alone cannot, which is to say *upwards* — a quote
          // with no hook reads as a subtitle belonging to this message.
          SizedBox(
            width: 22,
            height: 12,
            child: CustomPaint(painter: _ElbowPainter(theme.borderElevated)),
          ),
          const SizedBox(width: 6),
          if (message == null)
            Flexible(
              child: Text(
                'Original message unavailable',
                style: _quiet.copyWith(
                  color: theme.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else ...[
            Text(
              message.authorName,
              style: AppText.chip.copyWith(color: theme.textSecondary),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                MessageExcerpt.of(message),
                style: _quiet.copyWith(color: theme.textTertiary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The excerpt and the "nothing to show" line: label size, unemphasised, so
/// the quote sits under the message it belongs to rather than competing with
/// it.
final TextStyle _quiet = AppText.label.copyWith(fontWeight: FontWeight.w400);

/// Up from the baseline, then right — the same hairline weight as a resting
/// border, so the quote attaches to the conversation rather than boxing
/// itself off from it.
class _ElbowPainter extends CustomPainter {
  final Color color;

  const _ElbowPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final radius = K.radiusRow / 2;
    final path = Path()
      ..moveTo(size.width, size.height / 2)
      ..lineTo(radius, size.height / 2)
      ..quadraticBezierTo(0, size.height / 2, 0, size.height / 2 - radius)
      ..lineTo(0, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ElbowPainter old) => old.color != color;
}
