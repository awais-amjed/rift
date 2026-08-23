import 'package:flutter/material.dart';

import '../../logic/cubits/theme/theme_cubit.dart';
import '../../logic/services/message_markup.dart';
import '../theme/app_text.dart';
import 'emoji_text.dart';

/// Draws a message body: markup, mentions and emoji in one span tree.
///
/// The parsing lives in `logic/services/message_markup.dart`, which knows
/// nothing about Flutter. This is only the half that needs a theme — which
/// marks map to which styles, and which `@name` was real.
///
/// Emoji stay on their own font throughout: [emojiTextSpan] is applied per
/// stretch rather than to the whole line, so a bold message keeps its colour
/// emoji instead of dropping to the monochrome outlines the text font carries.
TextSpan messageMarkupSpan(
  String text, {
  required TextStyle base,
  required ThemeState theme,
  Set<String> mentionable = const {},
}) {
  final spans = parseMessageMarkup(text);
  return TextSpan(
    style: base,
    children: [
      for (final span in spans)
        if (span.isCode)
          // Code is one span with no emoji pass: inside code, a run of
          // characters that happens to look like an emoji is characters.
          TextSpan(text: span.text, style: _codeStyle(base, theme))
        else
          emojiTextSpan(
            span.text,
            style: _styleFor(span, base, theme, mentionable),
          ),
    ],
  );
}

/// Whether [text] names somebody in [mentionable].
///
/// Separate from rendering because the same question decides whether a message
/// is worth a notification, and answering it twice in two places is how the
/// highlight and the badge end up disagreeing.
bool mentionsAnyOf(String text, Set<String> names) {
  if (names.isEmpty) return false;
  for (final span in parseMessageMarkup(text)) {
    final mention = span.mention;
    if (mention != null && names.contains(mention.toLowerCase())) return true;
  }
  return false;
}

TextStyle? _styleFor(
  MarkupSpan span,
  TextStyle base,
  ThemeState theme,
  Set<String> mentionable,
) {
  final mention = span.mention;
  // Only a name that reaches somebody is lit up. Highlighting `@nobody` would
  // tell the writer they had pinged a person who will never see it.
  if (mention != null && mentionable.contains(mention.toLowerCase())) {
    return base.copyWith(
      color: theme.accentBright,
      fontWeight: FontWeight.w600,
      backgroundColor: theme.accentBright.withValues(alpha: 0.12),
    );
  }
  if (span.marks.isEmpty) return null;

  return base.copyWith(
    fontWeight: span.marks.contains(Marker.bold) ? FontWeight.w700 : null,
    fontStyle: span.marks.contains(Marker.italic) ? FontStyle.italic : null,
    decoration: span.marks.contains(Marker.strike)
        ? TextDecoration.lineThrough
        : null,
    decorationColor: theme.textTertiary,
  );
}

TextStyle _codeStyle(TextStyle base, ThemeState theme) => base.copyWith(
  fontFamily: AppText.mono,
  fontSize: (base.fontSize ?? 14) - 0.5,
  color: theme.textPrimary,
  backgroundColor: theme.bgTertiary,
);
