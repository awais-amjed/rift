import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/central_handle.dart';

void main() {
  group('normalize', () {
    test('trims and lowercases', () {
      expect(CentralHandle.normalize('  Noor  '), 'noor');
    });

    test('leaves an already-clean handle alone', () {
      expect(CentralHandle.normalize('noor_92'), 'noor_92');
    });
  });

  group('isValid', () {
    test('accepts letters, digits and underscores', () {
      expect(CentralHandle.isValid('noor_92'), isTrue);
    });

    test('accepts what normalising would fix', () {
      // The field and the cubit must agree, and the cubit normalises before
      // it checks — so a handle that only needs trimming has to pass here too.
      expect(CentralHandle.isValid('  Noor  '), isTrue);
    });

    test('rejects a handle below the minimum', () {
      expect(CentralHandle.isValid('no'), isFalse);
    });

    test('rejects a handle above the maximum', () {
      expect(
        CentralHandle.isValid('n' * (CentralHandle.maxLength + 1)),
        isFalse,
      );
    });

    test('accepts both bounds exactly', () {
      expect(CentralHandle.isValid('n' * CentralHandle.minLength), isTrue);
      expect(CentralHandle.isValid('n' * CentralHandle.maxLength), isTrue);
    });

    test('rejects punctuation and spaces inside', () {
      expect(CentralHandle.isValid('noor.92'), isFalse);
      expect(CentralHandle.isValid('noor 92'), isFalse);
      expect(CentralHandle.isValid('noor-92'), isFalse);
    });

    test('rejects an empty handle', () {
      expect(CentralHandle.isValid(''), isFalse);
      expect(CentralHandle.isValid('   '), isFalse);
    });

    test('anchors, so a valid run inside junk is still invalid', () {
      expect(CentralHandle.isValid('!!noor!!'), isFalse);
    });
  });

  /// The three handle fields used to accept anything: `AB Cd!` sat in a box
  /// under a line saying handles are a–z, 0–9 and underscore, and was refused
  /// only once the form was submitted — or, in the rename dialog, not
  /// explained at all, because the button simply stayed dark.
  group('the field folds as you type', () {
    /// One keystroke or paste, as the framework would deliver it.
    String typed(String before, String after, {int? caret}) {
      var value = TextEditingValue(
        text: after,
        selection: TextSelection.collapsed(offset: caret ?? after.length),
      );
      for (final formatter in CentralHandle.inputFormatters) {
        value = formatter.formatEditUpdate(
          TextEditingValue(
            text: before,
            selection: TextSelection.collapsed(offset: before.length),
          ),
          value,
        );
      }
      return value.text;
    }

    test('the handle that started this becomes a usable one', () {
      expect(typed('AB Cd', 'AB Cd!'), 'abcd');
    });

    test('a capital is folded rather than refused', () {
      // normalize() has always been willing to fix this, so the box shows
      // the fix instead of quietly applying it at submit.
      expect(typed('Noo', 'Noor'), 'noor');
    });

    test('spaces and punctuation never arrive', () {
      expect(typed('noor', 'noor 92'), 'noor92');
      expect(typed('noor', 'noor-92'), 'noor92');
      expect(typed('noor', 'noor.92'), 'noor92');
    });

    test('leaves an already-clean handle untouched', () {
      expect(typed('noor_9', 'noor_92'), 'noor_92');
    });

    test('whatever survives is what normalize would have produced', () {
      for (final raw in ['AB Cd!', '  Noor  ', '!!noor!!', 'Noor-92']) {
        final folded = typed('', raw);
        expect(folded, CentralHandle.normalize(folded));
        expect(folded, isNot(contains(' ')));
      }
    });

    test('the caret is counted through the fold, not carried over', () {
      // A paste that loses characters moves everything after them; an offset
      // taken from the unfolded text would land past the end of the field.
      var value = TextEditingValue(
        text: 'A B!c',
        selection: const TextSelection.collapsed(offset: 4),
      );
      for (final formatter in CentralHandle.inputFormatters) {
        value = formatter.formatEditUpdate(TextEditingValue.empty, value);
      }
      expect(value.text, 'abc');
      expect(value.selection.baseOffset, 2, reason: 'after "ab"');
      expect(value.selection.baseOffset, lessThanOrEqualTo(value.text.length));
    });
  });

  test('the stated rule quotes the bounds it enforces', () {
    // The sentence is shown to the user as the reason a handle was refused,
    // so it has to describe the regex actually doing the refusing.
    expect(CentralHandle.rule, contains('${CentralHandle.minLength}'));
    expect(CentralHandle.rule, contains('${CentralHandle.maxLength}'));
  });
}
