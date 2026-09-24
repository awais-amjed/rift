import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/open_link.dart';

/// The scheme allowlist in front of `launchUrl`.
///
/// Pure, so it is testable without a platform channel — which is the reason
/// the check lives in its own function rather than inline at each call site.
/// Everything refused here would otherwise have been handed to `xdg-open`,
/// an Android intent resolver or a Windows protocol handler, from a URL that
/// arrived inside somebody else's message.
void main() {
  group('isOpenableLink', () {
    test('opens the web', () {
      expect(isOpenableLink(Uri.parse('https://example.com/a?b=c#d')), isTrue);
      // Plain http too: a router, a NAS or a dev server on the LAN has no
      // certificate and refusing it would be a rule about the web, not safety.
      expect(isOpenableLink(Uri.parse('http://192.168.1.4:8080/')), isTrue);
      expect(isOpenableLink(Uri.parse('HTTPS://EXAMPLE.COM')), isTrue);
    });

    test('refuses a local file', () {
      expect(isOpenableLink(Uri.parse('file:///etc/passwd')), isFalse);
      expect(isOpenableLink(Uri.parse('file://host/share/x.desktop')), isFalse);
    });

    test('refuses an Android intent', () {
      // `intent://` names a component to start, with extras. On a phone this
      // is the difference between opening a page and opening another app.
      expect(
        isOpenableLink(
          Uri.parse('intent://scan/#Intent;scheme=zxing;package=com.x;end'),
        ),
        isFalse,
      );
    });

    test('refuses the schemes that are not addresses at all', () {
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,<script>1</script>',
        'vbscript:msgbox',
        'smb://host/share',
        'ms-msdt:/id',
      ]) {
        expect(isOpenableLink(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('refuses an address with no host to open it against', () {
      expect(isOpenableLink(Uri.parse('https://')), isFalse);
      expect(isOpenableLink(Uri.parse('/just/a/path')), isFalse);
      expect(isOpenableLink(Uri.parse('//example.com')), isFalse);
      expect(isOpenableLink(Uri.parse('')), isFalse);
    });

    test('refuses a scheme that only looks like the web', () {
      // A tap target drawn from a link preview says what the sender wanted it
      // to say, so "it displayed example.com" is not a check.
      expect(isOpenableLink(Uri.parse('httpx://example.com')), isFalse);
      expect(isOpenableLink(Uri.parse('https+unix://example.com')), isFalse);
    });
  });

  group('openExternalLink', () {
    test('refuses before it reaches the platform', () async {
      // No platform channel is registered in a unit test, so a URL that got
      // as far as `launchUrl` would throw rather than return false. Each of
      // these returning false is the guard answering first.
      for (final url in ['file:///etc/passwd', 'javascript:1', 'nonsense']) {
        expect(await openExternalLink(url), isFalse, reason: url);
      }
    });
  });
}
