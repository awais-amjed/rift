import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/text_safety.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The message body with the words the list flags covered, when the setting
/// says to cover.
///
/// Only the words: covering the whole message for one of them hid everything
/// else it said, and the sentence around a swear is nearly always the part
/// worth reading. In blur mode a "Show" at the end uncovers them, remembered
/// for the session by message rather than by widget; in hide mode there is
/// no way through. The row builds the body from whatever [text] this hands
/// it, so everything about deciding stays here.
class GuardedMessageText extends StatefulWidget {
  final String messageId;
  final String text;

  /// Builds the body from the text to show — the message, or a copy with the
  /// flagged words dotted out — and a span to end it with, which is the way
  /// to uncover them when there is one.
  final Widget Function(String text, InlineSpan? reveal) builder;

  const GuardedMessageText({
    super.key,
    required this.messageId,
    required this.text,
    required this.builder,
  });

  static final Set<String> _revealed = {};

  @visibleForTesting
  static void resetReveals() => _revealed.clear();

  @override
  State<GuardedMessageText> createState() => _GuardedMessageTextState();
}

class _GuardedMessageTextState extends State<GuardedMessageText> {
  // A span cannot own its recognizer, so the widget does.
  late final TapGestureRecognizer _reveal = TapGestureRecognizer()
    ..onTap = () =>
        setState(() => GuardedMessageText._revealed.add(widget.messageId));

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppCubit, SensitiveContentMode>(
      (c) => c.state.sensitiveContentMode,
    );
    if (mode == SensitiveContentMode.off ||
        GuardedMessageText._revealed.contains(widget.messageId)) {
      return widget.builder(widget.text, null);
    }
    final ranges = TextSafety.instance.sensitiveRanges(
      widget.messageId,
      widget.text,
    );
    if (ranges.isEmpty) return widget.builder(widget.text, null);

    final covered = TextSafety.cover(widget.text, ranges);
    if (mode != SensitiveContentMode.blur) return widget.builder(covered, null);

    return widget.builder(
      covered,
      TextSpan(
        text: '  Show',
        style: AppText.secondaryStrong.copyWith(
          color: context.theme.textTertiary,
        ),
        mouseCursor: SystemMouseCursors.click,
        recognizer: _reveal,
      ),
    );
  }
}
