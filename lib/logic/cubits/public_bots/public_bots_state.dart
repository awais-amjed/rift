part of 'public_bots_cubit.dart';

class PublicBotsState {
  // ── Browsing ──────────────────────────────────────────────

  final List<PublicBot> results;
  final String query;
  final String? tag;
  final BotSort sort;
  final bool loading;

  /// Whether a browse has ever completed. An empty [results] means "nothing
  /// matches" only after one has; before that it means "not asked yet".
  final bool hasBrowsed;

  /// Whether another page exists — proved by the row the query over-fetched,
  /// never inferred from a page being full.
  final bool hasMore;

  /// Whether a *further* page is in flight, as opposed to a fresh browse: one
  /// is a footer spinner under results, the other replaces them.
  final bool loadingMore;

  /// Bots whose heart is mid-flight, so a second tap is ignored rather than
  /// racing the first. Ids, because the row that shows it is rebuilt from the
  /// list and does not survive to hold a flag of its own.
  final Set<String> liking;

  // ── Publishing ────────────────────────────────────────────

  final List<PublicBot> myListings;

  /// `max_public_bots()`, or null before it has been read.
  final int? cap;

  final bool savingListing;

  final String? error;

  const PublicBotsState({
    this.results = const [],
    this.query = '',
    this.tag,
    this.sort = BotSort.top,
    this.loading = false,
    this.hasBrowsed = false,
    this.hasMore = false,
    this.loadingMore = false,
    this.liking = const {},
    this.myListings = const [],
    this.cap,
    this.savingListing = false,
    this.error,
  });

  /// Every tag carried by anything on screen, alphabetical — the browser's
  /// filter chips. Derived from the results rather than fetched, so a chip
  /// can only ever offer a filter with something behind it.
  List<String> get visibleTags {
    final tags = <String>{
      for (final bot in results) ...bot.tags,
      ?tag,
    }.toList();
    tags.sort();
    return tags;
  }

  /// True once the account holds as many listings as it may. Null [cap] is
  /// "not known yet", which must not read as "full".
  bool get atCap => cap != null && myListings.length >= cap!;

  PublicBotsState copyWith({
    List<PublicBot>? results,
    String? query,
    String? tag,
    BotSort? sort,
    bool? loading,
    bool? hasBrowsed,
    bool? hasMore,
    bool? loadingMore,
    Set<String>? liking,
    List<PublicBot>? myListings,
    int? cap,
    bool? savingListing,
    String? error,
    bool clearTag = false,
    bool clearError = false,
  }) {
    return PublicBotsState(
      results: results ?? this.results,
      query: query ?? this.query,
      tag: clearTag ? null : (tag ?? this.tag),
      sort: sort ?? this.sort,
      loading: loading ?? this.loading,
      hasBrowsed: hasBrowsed ?? this.hasBrowsed,
      hasMore: hasMore ?? this.hasMore,
      loadingMore: loadingMore ?? this.loadingMore,
      liking: liking ?? this.liking,
      myListings: myListings ?? this.myListings,
      cap: cap ?? this.cap,
      savingListing: savingListing ?? this.savingListing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
