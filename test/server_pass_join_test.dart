import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/resolved_invite.dart';
import 'package:rift/data/repositories/server_pass_repository.dart';

/// A link can need a Rift account (an admin's switch on the server). The app
/// says so before signing in when there is no account, and otherwise asks
/// central for a pass that vouches for it.
void main() {
  // Central makes the tag from the address it is given, and anybody handed a
  // pass can read the tag in it. So a join through a link that needs an
  // account goes to the server's own address, the one its pass names, and
  // the pass is handed to nobody else (test/server_pass_address_test.dart).
  group('where a join goes', () {
    const marked = {'needs_account': true};

    test("a marked link reaching the server another way goes to the server's "
        'own address', () {
      expect(
        joinAddress(
          linkUrl: 'http://192.168.1.6:8000',
          data: {...marked, 'public_url': 'https://rift.example/'},
        ),
        'https://rift.example',
      );
    });

    test('a marked link at the address the server gives stays as it is', () {
      expect(
        joinAddress(
          linkUrl: 'https://rift.example',
          data: {...marked, 'public_url': 'https://rift.example/'},
        ),
        'https://rift.example',
      );
    });

    test('a link that needs no account joins where it points', () {
      expect(
        joinAddress(
          linkUrl: 'http://192.168.1.6:8000',
          data: {'public_url': 'https://rift.example'},
        ),
        'http://192.168.1.6:8000',
      );
    });

    test('a server that gives no usable address is joined where the link '
        'points', () {
      for (final publicUrl in [
        null,
        '',
        'rift.example',
        'ftp://rift.example',
      ]) {
        expect(
          joinAddress(
            linkUrl: 'https://rift.example',
            data: {...marked, 'public_url': publicUrl},
          ),
          'https://rift.example',
        );
      }
    });
  });

  group('marking a link on a server too old for it', () {
    test('says the server needs an update', () {
      expect(
        inviteErrorText(
          "Could not find the 'needs_account' column of 'invites' in the "
          'schema cache',
          needsAccount: true,
        ),
        'This server needs a console update before a link can need a Rift '
        'account.',
      );
    });

    test('leaves every other failure as it came', () {
      expect(inviteErrorText('nope', needsAccount: true), 'nope');
      expect(inviteErrorText(null, needsAccount: false), isNull);
    });
  });

  group('what the server says about a link', () {
    test('needs_account is read', () {
      expect(needsAccountIn({'server_id': 's', 'needs_account': true}), isTrue);
    });

    test('a server from before the switch says nothing, which is no', () {
      expect(needsAccountIn({'server_id': 's'}), isFalse);
      expect(
        needsAccountIn({'server_id': 's', 'needs_account': 'yes'}),
        isFalse,
      );
    });

    test('whether a link needs an account is part of the invite', () {
      const base = ResolvedInvite(
        serverUrl: 'https://rift.example',
        inviteCode: 'abc',
        serverId: 's',
        serverName: 'S',
      );
      const marked = ResolvedInvite(
        serverUrl: 'https://rift.example',
        inviteCode: 'abc',
        serverId: 's',
        serverName: 'S',
        needsAccount: true,
      );
      expect(base.needsAccount, isFalse);
      expect(base == marked, isFalse);
    });
  });

  group("central's answer", () {
    test('a pass comes back as it is', () {
      expect(passFromResponse({'pass': 'p.s'}), (pass: 'p.s', error: null));
    });

    test('an unconfirmed email says what to do', () {
      expect(
        passFromResponse({'error': 'email_unconfirmed'}).error,
        "Confirm your Rift account's email first, then join again.",
      );
    });

    test('a lost sign-in says what to do', () {
      expect(
        passFromResponse({'error': 'not_authenticated'}).error,
        'Sign in to Rift again, then join again.',
      );
    });

    test('anything else is a plain failure, never a pass', () {
      final answer = passFromResponse({'error': 'bad_fields'});
      expect(answer.pass, isNull);
      expect(
        answer.error,
        "Rift couldn't vouch for your account. Try joining again.",
      );
      expect(passFromResponse('nonsense').pass, isNull);
    });
  });
}
