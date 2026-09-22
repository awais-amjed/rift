import 'package:flutter/material.dart';

import '../../logic/services/emoji_text.dart';

/// The style an emoji stretch is rendered with. Naming the colour font
/// directly — rather than adding it as a *fallback* — is the whole point: see
/// the note on `logic/services/emoji_text.dart`.
const TextStyle emojiRunStyle = TextStyle(
  fontFamily: emojiFontFamily,
  fontFamilyFallback: emojiFontFamilyFallback,
);

/// Emoji shown on their own, as the thing you pick or count.
///
/// Pictures rather than type, so they sit outside `AppText`'s six steps —
/// but on a scale of their own, not a size per call site.
class EmojiSize {
  /// Beside a count, in a reaction chip.
  static const TextStyle chip = TextStyle(
    fontFamily: emojiFontFamily,
    fontFamilyFallback: emojiFontFamilyFallback,
    fontSize: 13,
  );

  /// A cell in a picker grid.
  static const TextStyle grid = TextStyle(
    fontFamily: emojiFontFamily,
    fontFamilyFallback: emojiFontFamilyFallback,
    fontSize: 19,
  );

  /// The quick reactions across a phone's action sheet, sized for a thumb.
  static const TextStyle sheet = TextStyle(
    fontFamily: emojiFontFamily,
    fontFamilyFallback: emojiFontFamilyFallback,
    fontSize: 24,
  );
}

/// Builds a span for [text] with every emoji stretch handed to the colour
/// emoji font and everything else left on [style].
TextSpan emojiTextSpan(String text, {TextStyle? style}) {
  final runs = splitEmojiRuns(text);
  // The overwhelmingly common case — no emoji — costs one span, as before.
  if (runs.length == 1 && !runs.first.isEmoji) {
    return TextSpan(text: text, style: style);
  }
  return TextSpan(
    style: style,
    children: [
      for (final run in runs)
        TextSpan(text: run.text, style: run.isEmoji ? emojiRunStyle : null),
    ],
  );
}

/// [Text] that renders emoji in colour. Drop-in for message bodies and any
/// other user-authored string.
class EmojiText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const EmojiText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      emojiTextSpan(text, style: style),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// A controller that colours emoji *inside* the composer field, so what you
/// type looks like what you send.
class EmojiTextEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    // While an IME composing region is active the base implementation
    // underlines it; re-spanning the text would drop that, so defer.
    if (withComposing && value.composing.isValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return emojiTextSpan(text, style: style);
  }
}
