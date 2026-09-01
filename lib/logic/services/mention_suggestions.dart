import '../../data/classes/server_member.dart';

/// The `@` menu: who you can name, and what typing a name does to the text.
///
/// Pure, so the fiddly half is reachable without a composer — where the caret
/// counts as "inside a mention", what a query matches, and what the text looks
/// like afterwards. Every one of those is invisible from the outside until it
/// is wrong, and then it is wrong while somebody is mid-sentence.
///
/// **You pick a person and the text gets their username.** Display names can be
/// changed by their owner and can collide; usernames cannot, which is why they
/// are what a mention resolves against (see [Mentions]). Searching by display
/// name and writing a username is the whole point of the menu: it is the piece
/// that lets somebody type the name they know without the message depending on
/// it.
class MentionSuggestions {
  const MentionSuggestions._();

  /// Most people offered at once. Past this the list stops being a list.
  static const maxResults = 8;

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
  /// Writes the *username* and leaves a trailing space, because the next thing
  /// somebody types is a word and not more of the name. Returns the text
  /// unchanged when the caret is not in a mention, so a stale menu press cannot
  /// rewrite the middle of a sentence.
  static ({String text, int cursor}) apply(
    String text,
    int cursor,
    ServerMember member,
  ) {
    final query = queryAt(text, cursor);
    if (query == null) return (text: text, cursor: cursor);

    final start = cursor - query.length - 1;
    final inserted = '@${member.username} ';
    return (
      text: text.replaceRange(start, cursor, inserted),
      cursor: start + inserted.length,
    );
  }
}
