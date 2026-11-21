import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/constants.dart';
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

  /// Whether [text] is covered in this message's row — asked by what shows
  /// a message's words outside it (a reply's quote, a forward's card), which
  /// once drew in full what the row hid (review, Nov 22). Call from `build`.
  static bool covers(
    BuildContext context, {
    required String messageId,
    required String text,
  }) {
    final mode = context.select<AppCubit, SensitiveContentMode>(
      (c) => c.state.sensitiveContentMode,
    );
    if (mode == SensitiveContentMode.off || _revealed.contains(messageId)) {
      return false;
    }
    final verdict = TextSafety.instance.check(messageId, text);
    return verdict != null && verdict.isSensitive;
  }

  @visibleForTesting
  static void resetReveals() => _revealed.clear();

  @override
  State<GuardedMessageText> createState() => _GuardedMessageTextState();
}

class _GuardedMessageTextState extends State<GuardedMessageText> {
  @override
  Widget build(BuildContext context) {
    if (!GuardedMessageText.covers(
      context,
      messageId: widget.messageId,
      text: widget.text,
    )) {
      return widget.child;
    }

    final mode = context.read<AppCubit>().state.sensitiveContentMode;
    final canReveal = mode == SensitiveContentMode.blur;
    final themeState = context.theme;
    return MouseRegion(
      cursor: canReveal ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
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
              size: K.iconRow,
              color: themeState.textTertiary,
            ),
            Text(
              'Sensitive message',
              style: AppText.body.copyWith(color: themeState.textTertiary),
            ),
            Text(
              canReveal ? '· Press to show' : '· Hidden by your settings',
              style: AppText.secondary.copyWith(
                color: themeState.textQuaternary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
