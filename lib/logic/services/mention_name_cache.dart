/// What `@names` in the open channel resolve to, and which have been asked.
///
/// Two halves of one cache. They were once a field on the cubit and a map in
/// its state, and resetting the channel cleared the map while leaving the
/// field — so the cubit went on believing it had already asked about names it
/// no longer had answers for, and never asked again. Every `@name` in the
/// channel then drew as plain text for the life of the cubit, while the person
/// who *typed* it still saw it highlighted, because the composer's mention
/// menu refills the answers as a side effect. Only the reader saw the bug.
///
/// Holding both here means [reset] cannot clear one and forget the other.
class MentionNameCache {
  /// Lower-cased names already put to `members_by_usernames`.
  ///
  /// Kept apart from [names] on purpose: a name that resolved to *nobody* has
  /// still been asked, and must not be asked again for every message that
  /// mentions it.
  final Set<String> _asked = {};

  /// Lower-cased username → display name, for the ones that answered.
  final Map<String, String> _names = {};

  /// Username → display name for every name resolved in this channel.
  Map<String, String> get names => Map.unmodifiable(_names);

  /// The names in [candidates] that have not been asked about yet.
  ///
  /// Marks them asked as it goes: the caller is about to ask, and a second
  /// batch arriving mid-flight must not ask again.
  List<String> unasked(Iterable<String> candidates) {
    final wanted = <String>[];
    for (final candidate in candidates) {
      final name = candidate.toLowerCase();
      if (_asked.add(name)) wanted.add(name);
    }
    return wanted;
  }

  /// Record what came back, as lower-cased username → display name.
  void remember(Map<String, String> found) {
    for (final entry in found.entries) {
      _names[entry.key.toLowerCase()] = entry.value;
    }
  }

  /// Forget a batch that was never actually answered.
  ///
  /// A lookup that failed — offline, a token being refreshed, a channel key
  /// not ready — must not count as asked, or the names in it are never
  /// resolved again however many times they are seen.
  void forget(Iterable<String> names) {
    for (final name in names) {
      _asked.remove(name.toLowerCase());
    }
  }

  /// Drop everything. The open channel changed.
  ///
  /// Both halves, always: the answers are channel-scoped — a name that
  /// resolved to nobody in a private room may well resolve in the next one —
  /// and so the record of having asked is scoped the same way.
  void reset() {
    _asked.clear();
    _names.clear();
  }
}
