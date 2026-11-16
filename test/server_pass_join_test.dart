import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/resolved_invite.dart';
import 'package:rift/data/repositories/server_pass_repository.dart';

/// A link can need a Rift account (an admin's switch on the server). The app
/// says so before signing in when there is no account, and otherwise asks
/// central for a pass that vouches for it.
void main() {
  // Central makes the tag from the address it is given, so the pass names
  // the server's own address, which the server hands out — never whichever
  // one the link happened to use.
  group('the address a pass names', () {
    test("is the server's own when it says", () {
      expect(
        passAddress(
          linkUrl: 'http://192.168.1.6:8000',
          data: {'public_url': 'https://rift.example'},
        ),
        'https://rift.example',
      );
    });

    test("is the link's on a server that does not say", () {
      expect(
        passAddress(linkUrl: 'https://rift.example', data: {'server_id': 's'}),
        'https://rift.example',
      );
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
