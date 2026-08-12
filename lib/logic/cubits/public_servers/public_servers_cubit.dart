import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/public_server.dart';
import '../../../data/repositories/public_server_repository.dart';

part 'public_servers_state.dart';

/// The central server directory, from both ends: the browser reads [results],
/// the publish dialog reads [myListings].
///
/// One cubit rather than two because the same account owns both halves — a
/// listing you just published has to be able to leave the browser the moment
/// you delist it, and a cap you have just spent has to be reflected where you
/// spend it. It is ephemeral (nothing here is worth persisting; a listing is
/// only ever as good as the last read) and lazy, so an account that never opens
/// either dialog never touches central for this at all.
class PublicServersCubit extends Cubit<PublicServersState> {
  final PublicServerRepository _repo;

  /// Guards a slow browse landing after a newer one — typing in the search
  /// field fires a request per pause, and they can arrive out of order.
  int _browseId = 0;

  /// Debounce for the search field, cancelled on every keystroke.
  Timer? _debounce;

  PublicServersCubit({PublicServerRepository? repo})
    : _repo = repo ?? PublicServerRepository(),
      super(const PublicServersState());

  // ── Browsing ──────────────────────────────────────────────

  /// Re-run the current query. Called on open, on retry, and after the
  /// debounce set by [search].
  Future<void> browse() async {
    final browseId = ++_browseId;
    emit(state.copyWith(loading: true, clearError: true));

    final response = await _repo.browse(query: state.query, tag: state.tag);
    if (isClosed || browseId != _browseId) return;

    if (!response.success) {
      emit(state.copyWith(loading: false, error: response.error));
      return;
    }
    emit(
      state.copyWith(
        loading: false,
        results: response.data as List<PublicServer>,
        hasBrowsed: true,
        clearError: true,
      ),
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
        myListings: mine.data as List<PublicServer>,
        cap: cap.success ? cap.data as int : null,
        clearError: true,
      ),
    );
  }

  /// Create or update the listing for one server. Returns the saved row, or
  /// null on failure — [PublicServersState.error] carries the reason.
  Future<PublicServer?> publish({
    required String supabaseUrl,
    required String serverId,
    required String inviteCode,
    required String name,
    String? description,
    String? iconUrl,
    List<String> tags = const [],
    int memberCount = 0,
    bool isListed = true,
  }) async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final response = await _repo.publish(
      supabaseUrl: supabaseUrl,
      serverId: serverId,
      inviteCode: inviteCode,
      name: name,
      description: description,
      iconUrl: iconUrl,
      tags: tags,
      memberCount: memberCount,
      isListed: isListed,
    );
    if (isClosed) return null;

    if (!response.success) {
      emit(state.copyWith(savingListing: false, error: response.error));
      return null;
    }

    final saved = response.data as PublicServer;
    emit(
      state.copyWith(
        savingListing: false,
        myListings: _replacing(saved),
        clearError: true,
      ),
    );
    return saved;
  }

  /// Withdraw a listing. Unlike delisting, nothing is kept.
  Future<bool> remove(String listingId) async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final response = await _repo.remove(listingId);
    if (isClosed) return false;

    if (!response.success) {
      emit(state.copyWith(savingListing: false, error: response.error));
      return false;
    }
    emit(
      state.copyWith(
        savingListing: false,
        myListings: state.myListings.where((l) => l.id != listingId).toList(),
        results: state.results.where((l) => l.id != listingId).toList(),
        clearError: true,
      ),
    );
    return true;
  }

  /// The listing this client already holds for a server, if any. Read before a
  /// network call so the publish dialog opens filled in rather than empty and
  /// then jumping.
  PublicServer? listingFor(String supabaseUrl, String serverId) {
    for (final listing in state.myListings) {
      if (listing.supabaseUrl == supabaseUrl && listing.serverId == serverId) {
        return listing;
      }
    }
    return null;
  }

  List<PublicServer> _replacing(PublicServer saved) => [
    saved,
    for (final listing in state.myListings)
      if (listing.id != saved.id) listing,
  ];

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
