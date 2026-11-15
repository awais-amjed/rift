import 'dart:io';

import 'package:flutter/services.dart';

import '../helper_methods.dart';

/// Mozilla's trusted roots, added to the ones Dart reads from Windows.
///
/// Windows 10 and 11 hold only some of the roots they trust. The rest are
/// fetched from Microsoft the first time Windows' own TLS needs one, which a
/// browser or the updater's HTTP client sets off and Dart never does: Dart
/// checks certificates with BoringSSL against the roots Windows holds at
/// that moment, and a site whose root has not been fetched yet fails with
/// `CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate`
/// (dart-lang/sdk#52266, open since 2023). Found Nov 15 2026 on a Windows 10
/// PC whose every model download failed that way: github.com's new Sectigo
/// root had never been fetched there, while the app's servers (Let's Encrypt)
/// and the update check (Rust, with its own copy of these roots) worked.
///
/// The roots are added, not swapped in: a root a company or an antivirus put
/// into Windows still counts. Every HTTPS connection Dart makes afterwards
/// uses them — the servers, central, link previews, model downloads — which is
/// why this runs before any of those starts. The file is curl's extract of
/// Mozilla's list (`scripts/update_ca_roots.sh` refreshes it).
abstract final class TrustedRoots {
  static const asset = 'assets/certificates/mozilla_roots.pem';

  /// Adds the roots on Windows; elsewhere the system's list is complete.
  /// Never throws: without them the app still has Windows' own.
  static Future<void> addOnWindows() async {
    if (!Platform.isWindows) return;
    try {
      final pem = await rootBundle.load(asset);
      SecurityContext.defaultContext.setTrustedCertificatesBytes(
        pem.buffer.asUint8List(pem.offsetInBytes, pem.lengthInBytes),
      );
      HelperMethods.printDebug('TLS: added Mozilla\'s roots to Windows\'');
    } catch (e) {
      HelperMethods.printDebug('TLS: could not add Mozilla\'s roots – $e');
    }
  }
}
