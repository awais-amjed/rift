/// The shape of a tag the directory will accept, mirrored from the CHECK that
/// `public_servers.tags` and `public_bots.tags` both carry (central migration
/// 001) so a malformed one is refused while it is still being typed rather
/// than by a database error on save.
///
/// One vocabulary across the whole directory on purpose: a server and a bot
/// tagged `music` are found by the same word, and there is one validator to
/// keep in step with one constraint.
class DirectoryTags {
  /// Matches `^[a-z0-9-]{2,20}$` — the per-element check on `public_servers.tags`.
  static final _shape = RegExp(r'^[a-z0-9-]{2,20}$');

  /// The column's `cardinality(tags) <= 5`.
  static const maxCount = 5;

  static bool isValid(String tag) => _shape.hasMatch(tag);

  /// [committed] plus whatever is still sitting in the input, normalised.
  ///
  /// The editor turns typing into a chip on Enter, and nobody should have to
  /// know that: a tag typed and left in the box is a tag the person meant to
  /// add, so saving has to pick it up rather than discard it. Duplicates and
  /// anything over [maxCount] are dropped, exactly as adding it would have.
  static List<String> withPending(List<String> committed, String pending) {
    final out = [...committed];
    for (final tag in normaliseAll(pending)) {
      if (out.length >= maxCount) break;
      if (!out.contains(tag)) out.add(tag);
    }
    return out;
  }

  /// Fold free text into *tags*, splitting on commas.
  ///
  /// A comma separates, it does not fold. The field's own placeholder is
  /// `gaming, board-games` — two tags — so a comma that survived into the slug
  /// turned the example itself into the single tag `gaming-board-games`.
  /// Everything else is still folded rather than refused, by [normalise].
  static List<String> normaliseAll(String input) => [
    for (final part in input.split(','))
      if (normalise(part) case final tag?) tag,
  ];

  /// Fold free text into a tag, or null if nothing usable survives. Spaces
  /// become hyphens rather than being dropped, so "board games" is one tag
  /// instead of "boardgames".
  static String? normalise(String input) {
    final slug = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return isValid(slug) ? slug : null;
  }
}
