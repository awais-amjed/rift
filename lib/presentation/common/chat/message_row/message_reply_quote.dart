import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/services/message_excerpt.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// What this client knows about the message a reply names.
///
/// Three states, not two, and separating them is the whole job. "I have not
/// found it" and "it is not there" are different facts, and telling a reader
/// the second when the first is true says somebody deleted something they
/// did not — the same collapse ARCHITECTURE.md §4 warns about one level
/// down, between a message that is locked and one that was dropped.
enum ReplyOriginState {
  /// Still asking. The reference is out of the loaded page and the lookup
  /// is in flight.
  looking,

  /// Here, in the list. The jump is a scroll.
  present,

  /// Real and readable, further back than the page the reader has. The jump
  /// has to fetch its way there first.
  behind,

  /// The server answered, and there is no such row.
  gone,

  /// Nobody could tell: the lookup failed, or this surface has no way to
  /// ask. The one case "unavailable" is the true word for.
  unknown,
}

/// The line above a reply saying what it answers.
///
/// **What it draws is never the sender's account of what was there**: the
/// body carries an id and no text precisely so a replier cannot put words in
/// somebody else's mouth, so every word here comes from a message this
/// client fetched and verified itself, or from [state] saying there is none.
class MessageReplyQuote extends StatelessWidget {
  final ChatMessage? original;

  /// What the lookup found. Drives the wording when there is nothing to
  /// quote, and whether the line is worth pressing.
  final ReplyOriginState state;

  /// Take the reader to what this answers. Null when there is nothing to go
  /// to — which is the same condition as [original] being null, and is why
  /// the "unavailable" line is not a button: a control that cannot do its
  /// one job is worse than a sentence saying why.
  final VoidCallback? onJump;

  const MessageReplyQuote({
    super.key,
    this.original,
    this.onJump,
    this.state = ReplyOriginState.present,
  });

  @override
  Widget build(BuildContext context) {
    final message = original;
    final line = _line(context);
    if (message == null || onJump == null) return line;

    // Wrapped rather than given its own ground: the quote is a line of text
    // above a message, and a button-shaped one would read as chrome. The
    // cursor is what says it is pressable, and the row's own hover is
    // already lighting behind it.
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onJump, child: line),
    );
  }

  Widget _line(BuildContext context) {
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
                _absence,
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

extension on MessageReplyQuote {
  /// What to say when there is no message to quote.
  ///
  /// "Unavailable" survives only for the case it is actually true of: this
  /// client could not find out. A deletion is named as one, because that is
  /// a thing that happened and the reader can stop looking.
  String get _absence => switch (state) {
    ReplyOriginState.gone => 'Original message was deleted',
    ReplyOriginState.looking => 'Finding the original…',
    _ => 'Original message unavailable',
  };
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
