import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/message_markup.dart';

/// The contract is narrow and the failure mode is nasty: markup that misfires
/// eats characters out of somebody's message and there is no way for them to
/// tell. So most of these are about text that must come back *unchanged*.
void main() {
  List<MarkupSpan> parse(String s) => parseMessageMarkup(s);
  String flat(String s) => parse(s).map((e) => e.text).join();

  group('plain text', () {
    test('an ordinary line is a single span', () {
      final spans = parse('morning, the tiles are up');
      expect(spans.length, 1);
      expect(spans.single.marks, isEmpty);
      expect(spans.single.text, 'morning, the tiles are up');
    });

    test('empty in, empty out', () {
      expect(parse(''), isEmpty);
    });
  });

  group('marks', () {
    test('bold', () {
      expect(parse('a **b** c'), [
        const MarkupSpan('a '),
        const MarkupSpan('b', marks: {Marker.bold}),
        const MarkupSpan(' c'),
      ]);
    });

    test('italic with either delimiter', () {
      expect(parse('*a*').single.marks, {Marker.italic});
      expect(parse('_a_').single.marks, {Marker.italic});
    });

    test('strikethrough', () {
      expect(parse('~~gone~~').single.marks, {Marker.strike});
    });

    test('bold wins over italic, so ** is never two asterisks', () {
      expect(parse('**b**').single.marks, {Marker.bold});
    });

    test('marks nest', () {
      final inner = parse('**bold and *both* here**');
      expect(inner.first.marks, {Marker.bold});
      expect(inner.firstWhere((s) => s.text == 'both').marks, {
        Marker.bold,
        Marker.italic,
      });
    });
  });

  group('what must survive untouched', () {
    test('an unclosed delimiter is literal', () {
      expect(flat('**not bold'), '**not bold');
      expect(parse('**not bold').single.marks, isEmpty);
    });

    test('snake_case is not italic', () {
      // The one that matters: most usernames people pick have an underscore.
      final spans = parse('see message_markup_test for this');
      expect(spans.length, 1);
      expect(spans.single.marks, isEmpty);
    });

    test('a bare pair of asterisks is not empty bold', () {
      expect(flat('** **'), '** **');
    });

    test('maths and shrugs come out as typed', () {
      expect(flat('2 * 3 * 4'), '2 * 3 * 4');
    });

    test('a backslash escapes the next character', () {
      final spans = parse(r'\*not italic\*');
      expect(spans.single.text, '*not italic*');
      expect(spans.single.marks, isEmpty);
    });

    test('nothing without a complete pair of delimiters is touched', () {
      // Escapes are excluded on purpose: consuming the backslash is the point
      // of one, and they have their own test above.
      for (final s in [
        'a*b',
        '~~',
        '`',
        '**a*',
        '_a',
        'a_b_c',
        '***',
        '@',
        'https://example.com/a_b_c',
        'x**y',
        '5 ** 2',
        r'C:\Users\me',
      ]) {
        expect(flat(s), s, reason: 'round trip failed for: \$s');
      }
    });
  });

  group('code', () {
    test('inline code is marked', () {
      final spans = parse('run `flutter test` now');
      expect(spans[1].text, 'flutter test');
      expect(spans[1].isCode, isTrue);
    });

    test('code contents are literal, not markup', () {
      final spans = parse('`**not bold**`');
      expect(spans.single.text, '**not bold**');
      expect(spans.single.marks, {Marker.code});
    });

    test('a fenced block drops the newlines hugging its fences', () {
      final spans = parse('```\nline one\n```');
      expect(spans.single.text, 'line one');
      expect(spans.single.isCode, isTrue);
    });

    test('an unclosed backtick is a backtick', () {
      expect(flat('a ` b'), 'a ` b');
    });
  });

  group('mentions', () {
    test('an at-name is carried out separately', () {
      final spans = parse('ping @noor about it');
      final mention = spans.firstWhere((s) => s.mention != null);
      expect(mention.mention, 'noor');
      expect(mention.text, '@noor');
    });

    test('a mention keeps the marks around it', () {
      final spans = parse('**ping @noor**');
      final mention = spans.firstWhere((s) => s.mention != null);
      expect(mention.marks, {Marker.bold});
    });

    test('an email address is not a mention', () {
      expect(parse('mail a@b.com').any((s) => s.mention != null), isFalse);
    });

    test('a bare @ is just an @', () {
      expect(parse('@').single.mention, isNull);
      expect(flat('@ '), '@ ');
    });

    test('resolution is not this parser\'s job', () {
      // It reports what was typed; the renderer decides if it reached anyone.
      expect(parse('@nobody_at_all').first.mention, 'nobody_at_all');
    });
  });
}
