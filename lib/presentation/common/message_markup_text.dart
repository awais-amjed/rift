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
  Map<String, String> displayNames = const {},
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
            _display(span, displayNames),
            style: _styleFor(span, base, theme, mentionable),
          ),
    ],
  );
}

/// What a span reads as on screen.
///
/// A mention is stored as `@username`, because that is the only name that
/// resolves to one person and keeps resolving after somebody renames themselves
/// — see `Mentions`. It is *shown* as `@Display Name`, because that is the name
/// the room knows them by, and a message that says `@charlie` about somebody
/// everyone calls Sam is a message you have to translate while reading it.
///
/// A name nobody answers to is left exactly as written: it is not a mention of
/// anybody, and rewriting it would invent a person.
String _display(MarkupSpan span, Map<String, String> displayNames) {
  final mention = span.mention;
  if (mention == null) return span.text;
  final name = displayNames[mention.toLowerCase()];
  return name == null ? span.text : '@$name';
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
