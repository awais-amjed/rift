import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/enums/sensitive_content_mode.dart';
import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/services/text_safety.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// The message body, or a collapsed line standing in for it when the word
/// list flags it and the setting says to cover.
///
/// The text version of the image cover: one line saying why, a tap through
/// in blur mode, none in hide mode, and a reveal remembered for the session
/// by message rather than by widget. The row hands over the finished
/// [child] and the message it was built from; everything about deciding
/// lives here, so the row grows by a wrapper and nothing else.
class GuardedMessageText extends StatefulWidget {
  final String messageId;
  final String text;
  final Widget child;

  const GuardedMessageText({
    super.key,
    required this.messageId,
    required this.text,
    required this.child,
  });

  static final Set<String> _revealed = {};

  @visibleForTesting
  static void resetReveals() => _revealed.clear();

  @override
  State<GuardedMessageText> createState() => _GuardedMessageTextState();
}

class _GuardedMessageTextState extends State<GuardedMessageText> {
  @override
  Widget build(BuildContext context) {
    final mode = context.select<AppCubit, SensitiveContentMode>(
      (c) => c.state.sensitiveContentMode,
    );
    if (mode == SensitiveContentMode.off ||
        GuardedMessageText._revealed.contains(widget.messageId)) {
      return widget.child;
    }
    final verdict = TextSafety.instance.check(widget.messageId, widget.text);
    if (verdict == null || !verdict.isSensitive) return widget.child;

    final canReveal = mode == SensitiveContentMode.blur;
    final themeState = context.theme;
    return GestureDetector(
      onTap: canReveal
          ? () => setState(
              () => GuardedMessageText._revealed.add(widget.messageId),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 15,
            color: themeState.textTertiary,
          ),
          Text(
            'Sensitive message',
            style: AppText.body.copyWith(color: themeState.textTertiary),
          ),
          Text(
            canReveal ? '· Tap to show' : '· Hidden by your settings',
            style: AppText.secondary.copyWith(color: themeState.textQuaternary),
          ),
        ],
      ),
    );
  }
}
