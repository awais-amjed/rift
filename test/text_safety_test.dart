import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/text_safety.dart';

void main() {
  final safety = TextSafety.instance;

  setUpAll(() {
    safety.install([
      {'id': 'damn', 'match': 'da*mn', 'severity': 1},
      {
        'id': 'arse',
        'match': 'arse',
        'severity': 2,
        'exceptions': ['sp*', '*nal'],
      },
      {'id': 'fuck', 'match': 'fu*ck|fvck', 'severity': 3},
      {'id': 'ass', 'match': 'ass', 'severity': 1},
      {'id': 'slur', 'match': 'god damn|god-damn', 'severity': 2},
    ]);
  });

  group('normalising', () {
    test('undoes leetspeak, spacing and stretching', () {
      expect(TextSafety.normalize('F U C K'), contains('fuck'));
      expect(TextSafety.normalize('fvck'), contains('fvck'));
      expect(TextSafety.normalize(r'a$$'), contains('ass'));
      expect(TextSafety.normalize('fuuuuck'), contains('fuck'));
      expect(TextSafety.normalize('sh1t'), contains('shit'));
      expect(TextSafety.normalize('sh!t'), contains('shit'));
    });

    test('leaves numbers and punctuation that are not in disguise', () {
      expect(TextSafety.normalize('see you in 2024!').first, 'see you in 2024');
      expect(TextSafety.normalize(r'costs $5'), ['costs 5']);
    });

    test('keeps a genuine double letter in one of its forms', () {
      expect(TextSafety.normalize('ass'), contains('ass'));
    });
  });

  group('checking', () {
    test('flags a match, in any dress', () {
      expect(safety.check('m1', 'well fuck that')?.rule.id, 'fuck');
      expect(safety.check('m2', 'F.U.C.K')?.rule.id, 'fuck');
      expect(safety.check('m3', 'fuuuuck!!')?.rule.id, 'fuck');
      expect(safety.check('m4', 'god damn it')?.rule.id, 'slur');
      // The article before a spaced-out word is not part of it.
      expect(safety.check('m4b', 'you are a f u c k')?.rule.id, 'fuck');
    });

    test('whole words only: class is not ass, assist is not ass', () {
      expect(safety.check('m5', 'first class'), isNull);
      expect(safety.check('m6', 'let me assist'), isNull);
      expect(safety.check('m7', 'kick ass')?.rule.id, 'ass');
    });

    test('an exception phrase stands down the match', () {
      expect(safety.check('m8', 'a sparse arse'), isNull);
      expect(safety.check('m9', 'arse'), isNotNull);
    });

    test('mild words are found but not covered', () {
      final v = safety.check('m10', 'damn it');
      expect(v?.rule.id, 'damn');
      expect(v?.isSensitive, isFalse);
      expect(safety.check('m11', 'fuck')?.isSensitive, isTrue);
    });

    test('an edit is looked at afresh under the same id', () {
      expect(safety.check('m12', 'fine'), isNull);
      expect(safety.check('m12', 'fuck'), isNotNull);
    });
  });
}
