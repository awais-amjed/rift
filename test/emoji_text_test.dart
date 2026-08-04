import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/emoji_text.dart';

void main() {
  group('splitEmojiRuns', () {
    test('an empty string yields no runs', () {
      expect(splitEmojiRuns(''), isEmpty);
    });

    test('plain text is one text run', () {
      expect(splitEmojiRuns('hello there'), [
        const TextRun('hello there', isEmoji: false),
      ]);
    });

    test('only emoji is one emoji run', () {
      expect(splitEmojiRuns('😀'), [const TextRun('😀', isEmoji: true)]);
    });

    // The reported bug: these are the emoji that text fonts cover, so they
    // rendered as flat monochrome glyphs.
    test('the emoji that text fonts cover are still detected', () {
      for (final emoji in ['😀', '❤', '☺', '⭐', '✅', '➡']) {
        expect(splitEmojiRuns(emoji), [
          TextRun(emoji, isEmoji: true),
        ], reason: '$emoji should be an emoji run');
      }
    });

    test('mixed text splits at the emoji boundaries', () {
      expect(splitEmojiRuns('hi 😀 there'), [
        const TextRun('hi ', isEmoji: false),
        const TextRun('😀', isEmoji: true),
        const TextRun(' there', isEmoji: false),
      ]);
    });

    test('adjacent emoji merge into one run', () {
      expect(splitEmojiRuns('😀👍🎉'), [
        const TextRun('😀👍🎉', isEmoji: true),
      ]);
    });

    test('a ZWJ family stays a single run so the ligature survives', () {
      const family = '👨‍👩‍👧';
      expect(splitEmojiRuns(family), [const TextRun(family, isEmoji: true)]);
    });

    test('a skin-tone modifier rides with its base', () {
      const wave = '👋\u{1F3FD}';
      expect(splitEmojiRuns(wave), [const TextRun(wave, isEmoji: true)]);
    });

    test('a flag pair stays in one run', () {
      const flag = '\u{1F1FA}\u{1F1F8}';
      expect(splitEmojiRuns(flag), [const TextRun(flag, isEmoji: true)]);
    });

    test('a variation selector rides with its base', () {
      expect(splitEmojiRuns('❤️'), [const TextRun('❤️', isEmoji: true)]);
    });

    test('VS15 asks for the text glyph and is honoured', () {
      expect(splitEmojiRuns('❤︎'), [const TextRun('❤︎', isEmoji: false)]);
    });

    // Prose must not get handed to the emoji font.
    test('bare copyright and trademark stay text', () {
      expect(splitEmojiRuns('© Rift™ 2026'), [
        const TextRun('© Rift™ 2026', isEmoji: false),
      ]);
    });

    test('a digit is text but a keycap is emoji', () {
      expect(splitEmojiRuns('7'), [const TextRun('7', isEmoji: false)]);
      expect(splitEmojiRuns('7️⃣'), [const TextRun('7️⃣', isEmoji: true)]);
    });

    test('a dangling ZWJ does not swallow the rest of the string', () {
      final runs = splitEmojiRuns('😀‍abc');
      expect(runs.first, const TextRun('😀', isEmoji: true));
      expect(runs.last.isEmoji, isFalse);
      expect(runs.map((r) => r.text).join(), '😀‍abc');
    });

    test('every run concatenates back to the input', () {
      const samples = [
        'hi 😀 there',
        '👨‍👩‍👧 family',
        'no emoji at all',
        '❤️👍\u{1F3FF}!',
        '',
      ];
      for (final sample in samples) {
        expect(splitEmojiRuns(sample).map((r) => r.text).join(), sample);
      }
    });
  });
}
