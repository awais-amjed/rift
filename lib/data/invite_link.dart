/// A shareable invite is a single string that packs the server's URL and the
/// invite code together, so the joining user only has to paste one thing.
///
/// Three shapes are understood, because an invite has to survive being sent
/// through a chat app and clicked on a phone:
///
/// - **Plain** — `<server-url>#<code>`. What the invite dialog produces and
///   what every invite in the wild currently looks like. Pastes; never opens
///   the app by itself, because no client can claim an arbitrary host.
/// - **App scheme** — `rift://join#<server-url>#<code>`. Claimed by the
///   installed app on every platform without owning a domain. Not clickable in
///   most chat apps, so it is a handoff rather than something to share: a web
///   landing page hands one of these to the desktop app.
/// - **Web** — `https://<host>/join#<server-url>#<code>`. The clickable form,
///   for a host the project controls and Android has verified. The server URL
///   and the code ride in the *fragment*, which browsers never send, so the
///   landing page learns neither which server the invite is for nor its code.
///
/// Invite codes are pure hex, so `#` is unambiguous as a separator.
class InviteLink {
  final String serverUrl;
  final String inviteCode;

  const InviteLink({required this.serverUrl, required this.inviteCode});

  /// The scheme the installed app claims. See the class comment.
  static const String appScheme = 'rift';

  /// The path both wrapper forms use, so one router entry answers for both.
  static const String joinHost = 'join';

  /// The one host the project owns, and the only reason a link can be
  /// *clicked* rather than pasted.
  ///
  /// A self-hosted server's own address can't do this: Android verifies an
  /// https filter against `assetlinks.json` on the host, and no client can
  /// produce that for an address it has never seen. So every invite is wrapped
  /// in this one domain, whichever server it is actually for.
  ///
  /// It learns nothing by being in the middle. The server URL and the code
  /// ride in the fragment, which browsers never put on the wire — the landing
  /// page reads them in the visitor's own browser or not at all.
  ///
  /// A fork that would rather not point at this domain changes this one string
  /// and hosts the same two files. Links already handed out keep working
  /// either way: [parse] reads the plain form, and the fragment is read
  /// locally, so even an unreachable domain still pastes.
  static const String inviteHost = 'joinrift.app';

  /// Combines a server URL and invite code into a single shareable link.
  ///
  /// The clickable form. It opens the installed app directly on Android — the
  /// intent filter for [inviteHost] is verified against the site — and the
  /// landing page catches everyone else.
  static String build(String serverUrl, String inviteCode) {
    return 'https://$inviteHost/$joinHost'
        '#${_trim(serverUrl)}#${inviteCode.trim()}';
  }

  /// The bare `<server-url>#<code>` pair, with nothing in front of it.
  ///
  /// What invites looked like before there was a domain, and still the honest
  /// answer for anyone who would rather their invite not mention a host they
  /// don't run. Pastes into the join field; never opens the app by itself.
  static String buildPlain(String serverUrl, String inviteCode) {
    return '${_trim(serverUrl)}#${inviteCode.trim()}';
  }

  /// The same invite as something the installed app will open.
  ///
  /// Not what a person shares — see the class comment — but what a landing
  /// page points at once it knows the app is there.
  static String buildAppLink(String serverUrl, String inviteCode) {
    return '$appScheme://$joinHost#${_trim(serverUrl)}#${inviteCode.trim()}';
  }

  /// Parses any of the three shapes back into a URL and a code. Returns `null`
  /// if the input isn't a complete link.
  static InviteLink? parse(String input) {
    final trimmed = input.trim();

    // A wrapper first: `<wrapper>#<server-url>#<code>`. Read the plain way
    // round, the last `#` would split the *code* off correctly but leave the
    // wrapper glued to the front of the server URL.
    final parts = trimmed.split('#');
    if (parts.length == 3 && _looksLikeUrl(parts[1])) {
      return _make(parts[1], parts[2]);
    }

    final sep = trimmed.lastIndexOf('#');
    if (sep <= 0) return null;
    return _make(trimmed.substring(0, sep), trimmed.substring(sep + 1));
  }

  static InviteLink? _make(String serverUrl, String inviteCode) {
    final url = serverUrl.trim();
    final code = inviteCode.trim();
    if (url.isEmpty || code.isEmpty) return null;
    return InviteLink(serverUrl: url, inviteCode: code);
  }

  /// Enough to tell a wrapped server URL from an invite code, which is all
  /// this has to decide. A code is hex.
  static bool _looksLikeUrl(String value) => value.startsWith('http');

  static String _trim(String serverUrl) =>
      serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
}
