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

  test('the stated rule quotes the bounds it enforces', () {
    // The sentence is shown to the user as the reason a handle was refused,
    // so it has to describe the regex actually doing the refusing.
    expect(CentralHandle.rule, contains('${CentralHandle.minLength}'));
    expect(CentralHandle.rule, contains('${CentralHandle.maxLength}'));
  });
}
