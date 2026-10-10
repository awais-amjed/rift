import 'package:flutter/material.dart';

import '../../../../data/constants.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';

/// A member's `/` command as it reads in the channel: the verb in the accent,
/// then what was handed to the bot set like inline code.
///
/// Not run through message markup. A command is an instruction to a program
/// and the bot reads it character for character — `*` or `_` in a song title
/// is part of the title, and drawing it as emphasis would show something the
/// bot never got. The composer draws the same line the same way while it is
/// being typed (`ComposerCommandBackdrop`), so what is sent looks like what
/// was written.
TextSpan commandMessageSpan(
  String text, {
  required TextStyle base,
  required ThemeState theme,
}) {
  final trimmed = text.trim();
  final firstBreak = trimmed.indexOf(RegExp(r'\s'));
  final verb = firstBreak == -1 ? trimmed : trimmed.substring(0, firstBreak);
  final argument = firstBreak == -1 ? '' : trimmed.substring(firstBreak).trim();
  return TextSpan(
    style: base,
    children: [
      TextSpan(
        text: verb,
        style: base.copyWith(
          color: theme.accentBright,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (argument.isNotEmpty) ...[
        const TextSpan(text: ' '),
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CommandArgument(text: argument, theme: theme),
        ),
      ],
    ],
  );
}

/// What follows a command's verb, boxed like inline code.
///
/// A box of its own rather than a background on the text: a background is
/// painted flush against the glyphs, and code reads as code because of the
/// room around it. Wraps inside the box when it is long.
class CommandArgument extends StatelessWidget {
  final String text;
  final ThemeState theme;

  const CommandArgument({super.key, required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Text(text, style: AppText.code.copyWith(color: theme.textPrimary)),
    );
  }
}
