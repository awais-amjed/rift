import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/central_handle.dart';
import 'package:rift/logic/services/server_username.dart';

/// The join form used to check only that the box was not empty, so a server
/// accepted `Benny Smith!` as a username — a member nobody could ever mention,
/// because the mention parser stops at the space. These cases pin the shape to
/// what that parser can express.
void main() {
  group('ServerUsername.isValid', () {
    test('accepts the alphabet mentions can express', () {
      expect(ServerUsername.isValid('benny'), isTrue);
      expect(ServerUsername.isValid('Benny'), isTrue);
      expect(ServerUsername.isValid('benny_smith'), isTrue);
      expect(ServerUsername.isValid('benny.smith'), isTrue);
      expect(ServerUsername.isValid('benny-smith'), isTrue);
      expect(ServerUsername.isValid('b2'), isTrue);
    });

    test('refuses the name that started this', () {
      expect(ServerUsername.isValid('Benny Smith!'), isFalse);
    });

    test('refuses whitespace anywhere', () {
      expect(ServerUsername.isValid('benny smith'), isFalse);
      expect(ServerUsername.isValid('benny\tsmith'), isFalse);
    });

    test('refuses punctuation the parser would stop at', () {
      for (final bad in ['benny!', 'benny@home', 'benny#1', 'ben/ny', 'bé']) {
        expect(ServerUsername.isValid(bad), isFalse, reason: bad);
      }
    });

    test('enforces both bounds', () {
      expect(ServerUsername.isValid('a'), isFalse);
      expect(ServerUsername.isValid('a' * ServerUsername.maxLength), isTrue);
      expect(
        ServerUsername.isValid('a' * (ServerUsername.maxLength + 1)),
        isFalse,
      );
    });

    test('surrounding space is trimmed rather than refused', () {
      expect(ServerUsername.isValid('  benny  '), isTrue);
      expect(ServerUsername.normalize('  benny  '), 'benny');
    });

    test('case is kept — a server username is shown as typed', () {
      expect(ServerUsername.normalize('Benny'), 'Benny');
    });
  });

  /// The join form prefills the username from the central handle, so every
  /// handle has to clear this bar or that prefill would arrive already
  /// invalid.
  test('every central handle is a valid server username', () {
    expect(ServerUsername.acceptsCentralHandles(), isTrue);
    expect(ServerUsername.isValid('lana_clean'), isTrue);
    expect(CentralHandle.isValid('lana_clean'), isTrue);
  });

  group('ServerUsername.errorFor', () {
    test('says nothing about a valid name', () {
      expect(ServerUsername.errorFor('benny'), isNull);
    });

    test('names the reason rather than reciting the whole rule', () {
      expect(ServerUsername.errorFor(''), contains('Pick'));
      expect(ServerUsername.errorFor('a'), contains('at least'));
      expect(ServerUsername.errorFor('a' * 40), contains('at most'));
      expect(ServerUsername.errorFor('benny smith'), contains('spaces'));
      expect(ServerUsername.errorFor('benny!'), contains('Letters'));
    });
  });
}
