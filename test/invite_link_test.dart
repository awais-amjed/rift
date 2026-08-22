import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/invite_link.dart';

/// An invite has to survive being pasted into a text field, sent through a
/// chat app, and tapped on a phone — three routes that wrap it differently.
/// Reading it back is one function, and it has to stay able to read every
/// invite already in the wild.
void main() {
  const server = 'https://abc.supabase.co';
  const code = 'a1b2c3';

  group('parse', () {
    test('a plain link, which is every invite handed out so far', () {
      final link = InviteLink.parse('$server#$code');

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('a link the installed app was handed', () {
      final link = InviteLink.parse('rift://join#$server#$code');

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('a clickable web link', () {
      final link = InviteLink.parse('https://rift.example/join#$server#$code');

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('the wrapper does not become part of the server URL', () {
      // Split on the *last* '#' and the code comes out right while the server
      // reads as "https://rift.example/join#https://abc.supabase.co" — a URL
      // that resolves to nothing, and a join that fails for no visible reason.
      final link = InviteLink.parse('https://rift.example/join#$server#$code');

      expect(link?.serverUrl, isNot(contains('rift.example')));
    });

    test('surrounding whitespace is not part of the invite', () {
      final link = InviteLink.parse('  $server#$code \n');

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('a server URL with no scheme still reads as one', () {
      // Not everything pasted in has been through a browser.
      final link = InviteLink.parse('abc.supabase.co#$code');

      expect(link?.serverUrl, 'abc.supabase.co');
      expect(link?.inviteCode, code);
    });

    test('an address with no code is not an invite', () {
      expect(InviteLink.parse(server), isNull);
      expect(InviteLink.parse('$server#'), isNull);
    });

    test('a code with no address is not an invite', () {
      expect(InviteLink.parse('#$code'), isNull);
    });

    test('nothing is not an invite', () {
      expect(InviteLink.parse(''), isNull);
      expect(InviteLink.parse('   '), isNull);
    });
  });

  group('build', () {
    test('round trips through the plain form', () {
      final link = InviteLink.parse(InviteLink.build(server, code));

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('round trips through the app link', () {
      final link = InviteLink.parse(InviteLink.buildAppLink(server, code));

      expect(link?.serverUrl, server);
      expect(link?.inviteCode, code);
    });

    test('a trailing slash is not carried into the link', () {
      // '<url>/#<code>' and '<url>#<code>' would be two spellings of one
      // invite, and the server URL is a cache key elsewhere.
      expect(InviteLink.build('$server/', code), '$server#$code');
      expect(
        InviteLink.buildAppLink('$server//', code),
        endsWith('$server#$code'),
      );
    });

    test('the app link is one the platform can route', () {
      final uri = Uri.parse(InviteLink.buildAppLink(server, code));

      expect(uri.scheme, InviteLink.appScheme);
      expect(uri.host, InviteLink.joinHost);
    });
  });
}
