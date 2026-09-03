/// Trimming an over-fetched page back to size, and saying whether another one
/// follows.
///
/// Every paged read in the app asks the database for `limit + 1` rows. The row
/// past the page is what proves there is another page. Inferring it from a full
/// page instead — the obvious shortcut — lies whenever the collection is an
/// exact multiple of the page size: 50 messages would promise a fifty-first,
/// and the reader who scrolls gets a spinner for a page that comes back empty.
/// One spare row on the wire is cheaper than a count.
///
/// It lives on its own rather than inside `ChatMessageOps` because it is not
/// about chat: history, DM history and the member roster all page, and a third
/// caller reaching into a chat helper for it is how a shared rule ends up
/// copied. Each caller brings its own page size — how much history to read and
/// how many names fit in a sidebar are unrelated numbers, and one shared
/// default would only pretend otherwise.
abstract final class Paging {
  /// Trim [rows] back to [limit], and report whether the over-fetch found more.
  static ({List<T> rows, bool hasMore}) split<T>(
    List<T> rows, {
    required int limit,
  }) => (
    rows: rows.length > limit ? rows.sublist(0, limit) : rows,
    hasMore: rows.length > limit,
  );
}
