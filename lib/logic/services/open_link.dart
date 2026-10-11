import 'package:url_launcher/url_launcher.dart';

/// Hands a URL to the operating system, and refuses anything that is not a
/// web address.
///
/// The one place in the app that calls `launchUrl`, because the check has to
/// be somewhere every caller passes and a scheme allowlist spelled three
/// times is a scheme allowlist spelled twice.
///
/// **What this is for.** `LaunchMode.externalApplication` means whatever the
/// platform has registered for the scheme: `xdg-open` on Linux, an `intent://`
/// target on Android, a `file://` path or an `ms-` handler on Windows. Most of
/// the addresses Rift opens were written by somebody else — a link preview is
/// built on the sender's device and travels inside the sealed body, a bot
/// listing's source URL is whatever the publisher typed — so "open this" is an
/// instruction arriving from another person, and the tap that follows it is a
/// tap the reader believes is on a web link.
///
/// The message text path was never exposed: its linkifier matches `https?://`
/// and prefixes a bare host with `https://`, so it could only ever produce a
/// web address. The preview card read its URL straight out of the body, which
/// is the same address the same message drew as a card the reader was meant to
/// click. The guard belongs here rather than in either of them.
///
/// Returns false when the address was refused or the platform could not open
/// it, so a caller can say so rather than appearing to do nothing.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !isOpenableLink(uri)) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Whether [uri] is an address Rift will hand to the system.
///
/// `http` as well as `https`: plenty of what people link to on a LAN — a
/// router, a NAS, somebody's dev server — has no certificate and never will,
/// and refusing it would be a rule about the web rather than about safety. A
/// scheme-relative or bare-path URI has no scheme at all and is refused with
/// the rest, because there is no host to open it against.
bool isOpenableLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'https' || scheme == 'http') && uri.host.isNotEmpty;
}

/// Opens one of Rift's own folders in the system's file manager — its logs,
/// for someone sending them by hand. Never a path from anybody else, which is
/// why it is not [openExternalLink]: that refuses `file:` on purpose.
Future<bool> openOwnFolder(String path) =>
    launchUrl(Uri.directory(path), mode: LaunchMode.externalApplication);
