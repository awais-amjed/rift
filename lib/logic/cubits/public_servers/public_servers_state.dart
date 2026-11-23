part of 'public_servers_cubit.dart';

/// The public server directory: the current browse and its paging.
class PublicServersState extends Equatable {
  // ── Browsing ──────────────────────────────────────────────

  final List<PublicServer> results;
  final String query;
  final String? tag;
  final DirectorySort sort;
  final bool loading;

  /// Whether a browse has ever completed. An empty [results] means "nothing
  /// matches" only after one has; before that it means "not asked yet", and
  /// the two want very different things on screen.
  final bool hasBrowsed;

  /// Whether another page of the directory exists — proved by the row the
  /// query over-fetched, never inferred from a page being full.
  final bool hasMore;

  /// Whether a *further* page is in flight, as opposed to a fresh browse.
  /// Kept apart because the two draw differently: one is a footer spinner
  /// under results, the other replaces them.
  final bool loadingMore;

  /// The last further page failed. The rows already read stay on screen and
  /// the footer offers a retry, instead of one blip replacing the whole list
  /// with an error.
  final bool moreFailed;

  /// Listings whose like is in flight, so a second tap is dropped and the
  /// heart can stop answering until central has.
  final Set<String> liking;

  // ── Publishing ────────────────────────────────────────────

  final List<PublicServer> myListings;

  /// `max_public_servers()`, or null before it has been read.
  final int? cap;

  final bool savingListing;

  final String? error;

  const PublicServersState({
    this.results = const [],
    this.query = '',
    this.tag,
    this.sort = DirectorySort.top,
    this.loading = false,
    this.hasBrowsed = false,
    this.hasMore = false,
    this.loadingMore = false,
    this.moreFailed = false,
    this.liking = const {},
    this.myListings = const [],
    this.cap,
    this.savingListing = false,
    this.error,
  });

  /// Every tag carried by anything on screen, alphabetical — the browser's
  /// filter chips. Derived from the results rather than fetched, so the chips
  /// can only ever offer a filter that has something behind it.
  List<String> get visibleTags {
    final tags = <String>{
      for (final server in results) ...server.tags,
      ?tag,
    }.toList();
    tags.sort();
    return tags;
  }

  /// True once the account holds as many listings as it may. Null [cap] is
  /// "not known yet", which must not read as "full".
  bool get atCap => cap != null && myListings.length >= cap!;

  PublicServersState copyWith({
    List<PublicServer>? results,
    String? query,
    String? tag,
    DirectorySort? sort,
    bool? loading,
    bool? hasBrowsed,
    bool? hasMore,
    bool? loadingMore,
    bool? moreFailed,
    Set<String>? liking,
    List<PublicServer>? myListings,
    int? cap,
    bool? savingListing,
    String? error,
    bool clearTag = false,
    bool clearError = false,
  }) {
    return PublicServersState(
      results: results ?? this.results,
      query: query ?? this.query,
      tag: clearTag ? null : (tag ?? this.tag),
      sort: sort ?? this.sort,
      loading: loading ?? this.loading,
      hasBrowsed: hasBrowsed ?? this.hasBrowsed,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      moreFailed: moreFailed ?? this.moreFailed,
      liking: liking ?? this.liking,
      myListings: myListings ?? this.myListings,
      cap: cap ?? this.cap,
      savingListing: savingListing ?? this.savingListing,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
    results,
    query,
    tag,
    sort,
    loading,
    hasBrowsed,
    hasMore,
    loadingMore,
    moreFailed,
    SetProp(liking),
    myListings,
    cap,
    savingListing,
    error,
  ];
}
