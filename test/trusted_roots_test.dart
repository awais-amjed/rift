import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The roots TrustedRoots adds on Windows load as BoringSSL reads them, and
/// carry the ones the app's hosts need. Pure: no connection is made.
void main() {
  final pem = File('assets/certificates/mozilla_roots.pem');

  test('the bundled roots load into a security context', () {
    final context = SecurityContext(withTrustedRoots: false);
    expect(
      () => context.setTrustedCertificatesBytes(pem.readAsBytesSync()),
      returnsNormally,
    );
  });

  test('the bundle holds the roots behind GitHub and Let\'s Encrypt', () {
    final text = pem.readAsStringSync();
    expect('BEGIN CERTIFICATE'.allMatches(text).length, greaterThan(100));
    // github.com (Sectigo, Nov 2026) and every Let's Encrypt server.
    for (final root in [
      'Sectigo Public Server Authentication Root E46',
      'USERTrust ECC Certification Authority',
      'ISRG Root X1',
    ]) {
      expect(text, contains('\n$root\n'), reason: root);
    }
  });

  test('pubspec ships the bundle', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/certificates/mozilla_roots.pem'),
    );
  });
}
