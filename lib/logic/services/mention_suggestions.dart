import '../../data/classes/server_member.dart';

/// The `@` menu: who you can name, and what typing a name does to the text.
///
/// Pure, so the fiddly half is reachable without a composer — where the caret
/// counts as "inside a mention", what a query matches, and what the text looks
/// like afterwards. Every one of those is invisible from the outside until it
/// is wrong, and then it is wrong while somebody is mid-sentence.
///
/// **You see a display name; the message carries a username.** Display names can
/// be changed by their owner and can collide, so a mention resolves against the
/// username or it resolves against the wrong person (see [Mentions]). But
/// `@schematest` in a box, about somebody the room calls Awais, is a name you
/// have to translate while writing.
///
/// So the composer holds the display name and [toWire] swaps it for the username
/// on the way out. Doing it the other way round — holding the username and
/// *drawing* the display name — is not available: a text field maps the caret by
/// counting characters, so a rendered string of a different length puts the
/// cursor in the wrong place.
class MentionSuggestions {
  const MentionSuggestions._();

  /// Most people offered at once.
  ///
  /// Small on purpose: the menu floats over the conversation, so each row hides
  /// a line of what somebody just said. Past this you are reading a directory
  /// rather than picking a name, and the answer is nearly always the first one.
  ///
  /// The menu is sized to show exactly this many whole rows — a list whose last
  /// row is cut in half reads as a rendering bug rather than as more to scroll.
  static const maxResults = 4;

  /// The `@…` being typed at [cursor], without its `@`, or null if the caret is
  /// not in one.
  ///
  /// A mention starts at a word boundary — `a@b.com` is an address, not a
  /// mention of `b`, and the parser that draws the message agrees. It ends at
  /// whitespace, so once there is a space the menu closes rather than going on
  /// offering to replace what is now a sentence.
  static String? queryAt(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;

    final before = text.substring(0, cursor);
    final at = before.lastIndexOf('@');
    if (at == -1) return null;

    // Nothing between the `@` and the caret may be whitespace.
    final query = before.substring(at + 1);
    if (query.contains(RegExp(r'\s'))) return null;

    // A word character in front makes it part of that word.
    if (at > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(before[at - 1])) return null;

    return query;
  }

  /// Who [query] offers, best first.
  ///
  /// Matched against the display name *and* the username, because those are two
  /// different things somebody might be thinking of and neither is reliably the
  /// one they know. A prefix beats a match in the middle, so typing the start of
  /// a name puts that person first rather than somewhere in a list.
  ///
  /// Spaces in a display name are ignored on the display-name side, so `@animb`
  /// finds "Anim Bot" — a mention token cannot contain a space, so somebody
  /// typing a two-word name has no other way to reach them.
  static List<ServerMember> suggest(
    String query,
    Iterable<ServerMember> members, {
    String? excludeUserId,
  }) {
    final needle = query.trim().toLowerCase();
    final prefix = <ServerMember>[];
    final contains = <ServerMember>[];

    for (final member in members) {
      if (member.id == excludeUserId) continue;
      if (member.isBanned) continue;

      final username = member.username.toLowerCase();
      final display = member.displayName.toLowerCase();
      final squashed = display.replaceAll(' ', '');

      if (needle.isEmpty) {
        prefix.add(member);
      } else if (username.startsWith(needle) ||
          display.startsWith(needle) ||
          squashed.startsWith(needle)) {
        prefix.add(member);
      } else if (username.contains(needle) || squashed.contains(needle)) {
        contains.add(member);
      }
    }

    return [...prefix, ...contains].take(maxResults).toList(growable: false);
  }

  /// The text and caret after picking [member] for the mention at [cursor].
  ///
  /// Writes the *display name* — what the writer is looking at — and leaves a
  /// trailing space, because the next thing somebody types is a word and not
  /// more of the name. [toWire] turns it into a username before it is sent.
  ///
  /// Returns the text unchanged when the caret is not in a mention, so a stale
  /// menu press cannot rewrite the middle of a sentence.
  static ({String text, int cursor}) apply(
    String text,
    int cursor,
    ServerMember member,
  ) {
    final query = queryAt(text, cursor);
    if (query == null) return (text: text, cursor: cursor);

    final start = cursor - query.length - 1;
    final inserted = '@${member.displayName} ';
    return (
      text: text.replaceRange(start, cursor, inserted),
      cursor: start + inserted.length,
    );
  }

  /// Swap the display names somebody picked for the usernames a mention needs.
  ///
  /// [picked] is display name → username, built as each person was chosen. Only
  /// names that were actually picked are touched: a display name typed by hand
  /// is left alone, because the composer never established *which* person it
  /// meant and guessing is how a message pings a stranger with the same name.
  ///
  /// Longest first, so a name that contains another ("Sam" inside "Sam Two") is
  /// not half-replaced. Plain string matching rather than a regular expression,
  /// because a display name may contain anything a person can type.
  static String toWire(String text, Map<String, String> picked) {
    if (picked.isEmpty || text.isEmpty) return text;

    final names = picked.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    var out = text;
    for (final name in names) {
      final username = picked[name];
      if (username == null) continue;
      out = out.replaceAll('@$name', '@$username');
    }
    return out;
  }
}
