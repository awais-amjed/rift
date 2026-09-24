import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/public_bot.dart';
import '../../../data/repositories/public_bot_repository.dart';

part 'public_bots_state.dart';

/// The central bot directory, from both ends: the browser reads [results],
/// the listing dialog reads [myListings].
///
/// Deliberately the same shape as `PublicServersCubit` — one cubit for both
/// halves, ephemeral, and lazy, so an account that never opens either dialog
/// never touches central for this. The one thing it has that the server
/// directory does not is a like, which is the only way anybody changes a row
/// that isn't theirs.
class PublicBotsCubit extends Cubit<PublicBotsState> {
  final PublicBotRepository _repo;

  /// Guards a slow browse landing after a newer one — typing in the search
  /// field fires a request per pause, and they can arrive out of order.
  int _browseId = 0;

  /// Debounce for the search field, cancelled on every keystroke.
  Timer? _debounce;

  PublicBotsCubit({PublicBotRepository? repo})
    : _repo = repo ?? PublicBotRepository(),
      super(const PublicBotsState());

  // ── Browsing ──────────────────────────────────────────────

  /// Re-run the current query from the top. Called on open, on retry, after
  /// the debounce set by [search], and whenever the sort or tag changes.
  Future<void> browse() async {
    final browseId = ++_browseId;
    emit(state.copyWith(loading: true, clearError: true));

    final page = await _fetch(offset: 0);
    if (isClosed || browseId != _browseId || page == null) return;

    emit(
      state.copyWith(
        loading: false,
        results: page.results,
        hasMore: page.hasMore,
        hasBrowsed: true,
        clearError: true,
      ),
    );
  }

  /// Append the next page — what the list asks for as it is scrolled. Safe to
  /// call on every scroll frame: a call while one is in flight, or after the
  /// end, is a no-op.
  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final browseId = _browseId;
    emit(state.copyWith(loadingMore: true));

    final page = await _fetch(offset: state.results.length);
    if (isClosed || browseId != _browseId) return;
    if (page == null) {
      emit(state.copyWith(loadingMore: false));
      return;
    }

    emit(
      state.copyWith(
        loadingMore: false,
        results: [...state.results, ...page.results],
        hasMore: page.hasMore,
        clearError: true,
      ),
    );
  }

  /// One page of the directory, or null when the request failed — in which
  /// case [PublicBotsState.error] carries the reason.
  Future<({List<PublicBot> results, bool hasMore})?> _fetch({
    required int offset,
  }) async {
    final response = await _repo.browse(
      query: state.query,
      tag: state.tag,
      sort: state.sort,
      offset: offset,
    );
    if (isClosed) return null;
    if (!response.success) {
      emit(state.copyWith(loading: false, error: response.error));
      return null;
    }
    final data = response.data as Map<String, dynamic>;
    return (
      results: data['results'] as List<PublicBot>,
      hasMore: data['has_more'] == true,
    );
  }

  /// A keystroke in the search field. The request waits for a pause, but the
  /// text lands immediately — the field is not going to stutter behind a timer.
  void search(String query) {
    if (query == state.query) return;
    emit(state.copyWith(query: query));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), browse);
  }

  /// Filter by tag, or clear it by passing the one already selected.
  void toggleTag(String tag) {
    _debounce?.cancel();
    emit(
      state.tag == tag
          ? state.copyWith(clearTag: true)
          : state.copyWith(tag: tag),
    );
    unawaited(browse());
  }

  /// Change the order. Top or new — see [BotSort].
  void setSort(BotSort sort) {
    if (sort == state.sort) return;
    _debounce?.cancel();
    emit(state.copyWith(sort: sort));
    unawaited(browse());
  }

  // ── Liking ────────────────────────────────────────────────

  /// Like or unlike, and keep the count the row shows in step.
  ///
  /// The heart moves when central answers, not before: a like is a write to
  /// somebody else's listing, and a filled heart that turns out to have been
  /// refused — no handle claimed, say — is the one case where showing the
  /// outcome early is showing the wrong thing. A second tap while the first
  /// is in flight is dropped rather than queued.
  Future<void> toggleLike(String botId) async {
    if (state.liking.contains(botId)) return;
    final current = _botById(botId);
    if (current == null) return;

    emit(state.copyWith(liking: {...state.liking, botId}, clearError: true));

    final wanted = !current.likedByMe;
    final response = await _repo.setLiked(botId, liked: wanted);
    if (isClosed) return;

    final done = {...state.liking}..remove(botId);
    if (!response.success) {
      emit(state.copyWith(liking: done, error: response.error));
      return;
    }

    // The count comes back from central rather than being adjusted here: a
    // trigger recounts it from `bot_likes`, and somebody else may have liked
    // the same bot in between. Null means the like was already there.
    final count = response.data as int?;
    emit(
      state.copyWith(
        liking: done,
        results: _replacing(
          botId,
          (bot) => bot.copyWith(likedByMe: wanted, likeCount: count),
        ),
      ),
    );
  }

  PublicBot? _botById(String botId) {
    for (final bot in state.results) {
      if (bot.id == botId) return bot;
    }
    return null;
  }

  List<PublicBot> _replacing(String botId, PublicBot Function(PublicBot) edit) {
    return [
      for (final bot in state.results)
        if (bot.id == botId) edit(bot) else bot,
    ];
  }

  // ── Publishing ────────────────────────────────────────────

  /// Load the caller's own listings and the cap they count against.
  Future<void> loadMine() async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final results = await Future.wait([_repo.myListings(), _repo.cap()]);
    if (isClosed) return;

    final mine = results[0];
    final cap = results[1];
    if (!mine.success) {
      emit(state.copyWith(savingListing: false, error: mine.error));
      return;
    }
    emit(
      state.copyWith(
        savingListing: false,
        myListings: mine.data as List<PublicBot>,
        cap: cap.success ? cap.data as int : null,
        clearError: true,
      ),
    );
  }

  /// Create ([id] null) or edit one of the caller's own listings. Returns the
  /// saved row, or null on failure — [PublicBotsState.error] carries why.
  Future<PublicBot?> publish({
    String? id,
    required String name,
    required String sourceUrl,
    String? description,
    String? iconPath,
    List<String> tags = const [],
    Map<String, dynamic>? manifest,
    bool isListed = true,
  }) async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final response = await _repo.publish(
      id: id,
      name: name,
      sourceUrl: sourceUrl,
      description: description,
      iconPath: iconPath,
      tags: tags,
      manifest: manifest,
      isListed: isListed,
    );
    if (isClosed) return null;

    if (!response.success) {
      emit(state.copyWith(savingListing: false, error: response.error));
      return null;
    }

    final saved = response.data as PublicBot;
    emit(
      state.copyWith(
        savingListing: false,
        myListings: [
          saved,
          for (final listing in state.myListings)
            if (listing.id != saved.id) listing,
        ],
        clearError: true,
      ),
    );
    return saved;
  }

  /// Withdraw a listing. Unlike delisting, nothing is kept — the likes go too.
  Future<bool> remove(String botId) async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final response = await _repo.remove(botId);
    if (isClosed) return false;

    if (!response.success) {
      emit(state.copyWith(savingListing: false, error: response.error));
      return false;
    }
    emit(
      state.copyWith(
        savingListing: false,
        myListings: state.myListings.where((l) => l.id != botId).toList(),
        results: state.results.where((l) => l.id != botId).toList(),
        clearError: true,
      ),
    );
    return true;
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
