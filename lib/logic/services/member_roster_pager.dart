import '../../data/classes/member_page.dart';

/// Walks a paged roster and remembers what it has been given.
///
/// The roster arrives a page at a time (`member_directory`), and two surfaces read
/// it that way — the members dialog and the member sidebar. What they share is
/// not the rendering but the bookkeeping: where the next page resumes, whether
/// one is already in flight, whether the end has been reached, and how to throw
/// all of it away when the question changes. That is what lives here.
///
/// It knows nothing about Flutter or about a cubit: it is handed [fetchPage]
/// and calls it. So the awkward cases — a second request while one is in
/// flight, a page landing after a reset, an end reached exactly on a page
/// boundary — are reachable in a test rather than only on a big server.
class MemberRosterPager {
  /// Fetches one page starting after the given cursor, or the first page for
  /// null. A null return is a failure, which stops the walk without pretending
  /// the end was reached.
  final Future<MemberPage?> Function(({String name, String id})? after)
  fetchPage;

  MemberRosterPager({required this.fetchPage});

  MemberPage _loaded = MemberPage.empty;

  /// Whether the first page has been asked for at all. Distinct from an empty
  /// result: a server with no members and a roster nobody has opened yet look
  /// identical in [loaded], and only one of them should stop [next] asking.
  bool _started = false;

  bool _busy = false;

  /// Bumped by [reset] so a page still in flight is dropped when it lands
  /// rather than appended to the list it no longer belongs to.
  int _generation = 0;

  /// Everything loaded so far, in order.
  MemberPage get loaded => _loaded;

  /// Whether a page is in flight.
  bool get busy => _busy;

  /// Whether asking again would produce anything.
  bool get hasMore => !_started || _loaded.hasMore;

  /// Whether the first page has landed, so a caller can tell "loading" from
  /// "nobody here".
  bool get isLoaded => _started && !_busy;

  /// Throw away what has been loaded and start again from the top.
  ///
  /// For when the question changes — a different server, a different channel, a
  /// member joining or leaving. Anything in flight is abandoned rather than
  /// awaited: it is an answer to the old question.
  void reset() {
    _generation++;
    _loaded = MemberPage.empty;
    _started = false;
    _busy = false;
  }

  /// Fetch the next page and append it. Returns whether [loaded] changed.
  ///
  /// Safe to call on every scroll frame: a call while one is in flight, or
  /// after the end has been reached, is a no-op rather than a duplicate
  /// request. That is the whole reason the guard is here and not in each
  /// scroll listener.
  Future<bool> next() async {
    if (_busy || !hasMore) return false;
    final generation = _generation;
    _busy = true;

    final page = await fetchPage(_loaded.cursor);
    if (generation != _generation) return false;

    _busy = false;
    if (page == null) return false;
    _started = true;
    _loaded = _loaded.followedBy(page);
    return true;
  }
}
