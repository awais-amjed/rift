/// A shareable invite is a single string that packs the server's URL and the
/// invite code together, so the joining user only has to paste one thing.
///
/// Format: `<server-url>#<invite-code>` — e.g.
/// `https://xxxxx.supabase.co#a1b2c3…`. Invite codes are pure hex, so the
/// `#` separator is unambiguous: everything before the last `#` is the URL,
/// everything after is the code.
class InviteLink {
  final String serverUrl;
  final String inviteCode;

  const InviteLink({required this.serverUrl, required this.inviteCode});

  /// Combines a server URL and invite code into a single shareable link.
  static String build(String serverUrl, String inviteCode) {
    final url = serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return '$url#${inviteCode.trim()}';
  }

  /// Parses a combined invite link back into its URL and code. Returns `null`
  /// if the input isn't a complete link (missing the code or the URL).
  static InviteLink? parse(String input) {
    final trimmed = input.trim();
    final sep = trimmed.lastIndexOf('#');
    if (sep <= 0) return null;

    final serverUrl = trimmed.substring(0, sep).trim();
    final inviteCode = trimmed.substring(sep + 1).trim();
    if (serverUrl.isEmpty || inviteCode.isEmpty) return null;

    return InviteLink(serverUrl: serverUrl, inviteCode: inviteCode);
  }
}
