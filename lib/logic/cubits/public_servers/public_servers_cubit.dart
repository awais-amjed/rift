import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/equality_props.dart';
import '../../../data/classes/public_server.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/directory_sort.dart';
import '../../../data/enums/listing_kind.dart';
import '../../../data/enums/report_reason.dart';
import '../../../data/repositories/listing_report_repository.dart';
import '../../../data/repositories/public_server_repository.dart';
import '../../services/directory_icon_publish.dart';

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
  final ListingReportRepository _reports;

  /// Guards a slow browse landing after a newer one — typing in the search
  /// field fires a request per pause, and they can arrive out of order.
  int _browseId = 0;

  /// Debounce for the search field, cancelled on every keystroke.
  Timer? _debounce;

  PublicServersCubit({
    PublicServerRepository? repo,
    ListingReportRepository? reports,
  }) : _repo = repo ?? PublicServerRepository(),
       _reports = reports ?? ListingReportRepository(),
       super(const PublicServersState());

  /// The signed-in central account — a listing's own publisher gets no
  /// Report button on it.
  String? get currentUserId => _repo.currentUserId;

  /// Report one of the listings on screen to Rift's moderators. Handed back
  /// rather than emitted: the dialog that asked is the one place that says
  /// whether it worked, and nothing in the list changes.
  Future<APIResponse> report(
    String listingId,
    ReportReason reason,
    String? details,
  ) => _reports.report(
    kind: ListingKind.server,
    listingId: listingId,
    reason: reason,
    details: details,
  );

  // ── Browsing ──────────────────────────────────────────────

  /// Re-run the current query from the top. Called on open, on retry, and
  /// after the debounce set by [search].
  Future<void> browse() async {
    final browseId = ++_browseId;
    // A page still on its way belongs to the browse this one replaces.
    emit(
      state.copyWith(
        loading: true,
        loadingMore: false,
        moreFailed: false,
        clearError: true,
      ),
    );

    final page = await _fetch(offset: 0);
    if (isClosed || browseId != _browseId) return;
    if (page.error != null) {
      emit(state.copyWith(loading: false, error: page.error));
      return;
    }

    emit(
      state.copyWith(
        loading: false,
        results: page.results!,
        hasMore: page.hasMore,
        hasBrowsed: true,
        clearError: true,
      ),
    );
  }

  /// Append the next page — what the list asks for as it is scrolled.
  ///
  /// The directory used to be one page of 50 with no way to ask for the next,
  /// so the 51st listed server could not be found at all and nothing on screen
  /// said so. Safe to call on every scroll frame: a call while one is in
  /// flight, or after the end, is a no-op, and so is one after a page failed
  /// until [retry] says to ask again — scrolling must not hammer central.
  Future<void> loadMore({bool retry = false}) async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    if (state.moreFailed && !retry) return;
    final browseId = _browseId;
    emit(state.copyWith(loadingMore: true, moreFailed: false));

    final page = await _fetch(offset: state.results.length);
    if (isClosed || browseId != _browseId) return;
    if (page.error != null) {
      // The rows already on screen stay: a blip on page three is not a
      // reason to take away pages one and two.
      emit(state.copyWith(loadingMore: false, moreFailed: true));
      return;
    }

    emit(
      state.copyWith(
        loadingMore: false,
        results: [...state.results, ...page.results!],
        hasMore: page.hasMore,
        clearError: true,
      ),
    );
  }

  /// One page of the directory, or why not. Emits nothing: whether the
  /// answer still matters is the caller's to decide, and a slow failure
  /// emitted here replaced a newer browse's results with an error.
  Future<({List<PublicServer>? results, bool hasMore, String? error})> _fetch({
    required int offset,
  }) async {
    final response = await _repo.browse(
      query: state.query,
      tag: state.tag,
      sort: state.sort,
      offset: offset,
    );
    if (!response.success) {
      return (
        results: null,
        hasMore: false,
        error: response.error ?? 'Could not reach the directory.',
      );
    }
    final data = response.data as Map<String, dynamic>;
    return (
      results: data['results'] as List<PublicServer>,
      hasMore: data['has_more'] == true,
      error: null,
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

  /// Change the order. Top or new — see [DirectorySort].
  void setSort(DirectorySort sort) {
    if (sort == state.sort) return;
    _debounce?.cancel();
    emit(state.copyWith(sort: sort));
    unawaited(browse());
  }

  // ── Liking ────────────────────────────────────────────────

  /// Like or unlike, and keep the count the row shows in step. Answers the
  /// refusal, if central refused, for the browser to show: it is not a
  /// failure of the list, which stays as it was.
  ///
  /// As `PublicBotsCubit.toggleLike`: the heart moves when central answers,
  /// since a like can be refused (no handle claimed), and a second tap while
  /// the first is in flight is dropped.
  Future<String?> toggleLike(String listingId) async {
    if (state.liking.contains(listingId)) return null;
    final current = _resultById(listingId);
    if (current == null) return null;

    emit(
      state.copyWith(liking: {...state.liking, listingId}, clearError: true),
    );

    final wanted = !current.likedByMe;
    final response = await _repo.setLiked(listingId, liked: wanted);
    if (isClosed) return null;

    final done = {...state.liking}..remove(listingId);
    if (!response.success) {
      emit(state.copyWith(liking: done));
      return response.error ?? 'Could not save that like.';
    }

    // Re-read from central, since somebody else may have liked it in
    // between. Null means the like was already there.
    final count = response.data as int?;
    emit(
      state.copyWith(
        liking: done,
        results: [
          for (final server in state.results)
            if (server.id == listingId)
              server.copyWith(likedByMe: wanted, likeCount: count)
            else
              server,
        ],
      ),
    );
    return null;
  }

  PublicServer? _resultById(String listingId) {
    for (final server in state.results) {
      if (server.id == listingId) return server;
    }
    return null;
  }

  // ── Publishing ────────────────────────────────────────────

  /// Whether the server is already in the directory, by anybody's hand.
  /// Answers false when central cannot be asked: the join flow then offers
  /// the listing page, which is the safe direction to be wrong in.
  Future<bool> isListed({
    required String supabaseUrl,
    required String serverId,
  }) async {
    final response = await _repo.isListed(
      supabaseUrl: supabaseUrl,
      serverId: serverId,
    );
    return response.success && response.data == true;
  }

  /// [serverId]'s listing as anybody browsing the directory sees it: null
  /// when it is not listed, is hidden by a moderator, or central cannot be
  /// asked. For the server's profile, which shows its description and tags.
  ///
  /// Filtered here as [browse] is, because the policy also shows a publisher
  /// their own delisted or hidden row, and the profile would then show an
  /// admin a description nobody else sees.
  Future<PublicServer?> publicListing({
    required String supabaseUrl,
    required String serverId,
  }) async {
    final response = await _repo.listingFor(
      supabaseUrl: supabaseUrl,
      serverId: serverId,
    );
    final listing = response.success ? response.data as PublicServer? : null;
    if (listing == null || !listing.isListed || listing.hiddenAt != null) {
      return null;
    }
    return listing;
  }

  /// Load the caller's own listings and the cap they count against. Answers
  /// whether it worked; [PublicServersState.error] says why not.
  Future<bool> loadMine() async {
    emit(state.copyWith(savingListing: true, clearError: true));

    final results = await Future.wait([_repo.myListings(), _repo.cap()]);
    if (isClosed) return false;

    final mine = results[0];
    final cap = results[1];
    if (!mine.success) {
      emit(state.copyWith(savingListing: false, error: mine.error));
      return false;
    }
    emit(
      state.copyWith(
        savingListing: false,
        myListings: mine.data as List<PublicServer>,
        cap: cap.success ? cap.data as int : null,
        clearError: true,
      ),
    );
    return true;
  }

  /// The server's listing as anybody signed in may read it — listed and not
  /// hidden, unless it is the caller's own — whoever published it. For the
  /// Discovery panel, which must not draw "not listed" over a listing another
  /// admin made. `ok` is false when central could not be asked.
  Future<({bool ok, PublicServer? listing})> anyListing({
    required String supabaseUrl,
    required String serverId,
  }) async {
    final response = await _repo.listingFor(
      supabaseUrl: supabaseUrl,
      serverId: serverId,
    );
    if (!response.success) return (ok: false, listing: null);
    return (ok: true, listing: response.data as PublicServer?);
  }

  /// Create or update the listing for one server. Returns the saved row, or
  /// null on failure — [PublicServersState.error] carries the reason.
  ///
  /// [listingToken] is a one-time proof, obtained from the server being
  /// listed, that an admin of it asked for this. Central redeems it against
  /// that server's own domain before writing anything — see the
  /// `publish_server` edge function — because central cannot otherwise tell an
  /// administrator from any other member.
  Future<PublicServer?> publish({
    required String supabaseUrl,
    required String serverId,
    required String inviteCode,
    required String name,
    required String listingToken,
    String? description,

    /// The server's **own** icon address, not a listing path. The bytes are
    /// copied into central here so the directory never fetches a picture from
    /// the publisher's host — see [DirectoryIconPublish]. Null, and a failed
    /// copy, both mean the listing draws its initial.
    String? iconSourceUrl,

    /// The picture the listing already has, kept when the copy of
    /// [iconSourceUrl] fails rather than taken off the listing by a timeout.
    String? keepIconPath,
    List<String> tags = const [],
    int memberCount = 0,
    bool isListed = true,
  }) async {
    emit(state.copyWith(savingListing: true, clearError: true));

    // Before the publish rather than after: a listing that named an object
    // which had not been stored yet would draw nothing until the next save.
    final icon = await DirectoryIconPublish.copyToCentral(iconSourceUrl);
    if (isClosed) return null;
    final iconPath = icon.failed ? keepIconPath : icon.path;

    final response = await _repo.publish(
      supabaseUrl: supabaseUrl,
      serverId: serverId,
      inviteCode: inviteCode,
      name: name,
      listingToken: listingToken,
      description: description,
      iconPath: iconPath,
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
  ///
  /// The address compared loosely ([Server.sameUrl]): central keys a listing
  /// on the host however it is spelled, and another device may have
  /// published it with a trailing slash this one's list does not have.
  PublicServer? listingFor(String supabaseUrl, String serverId) {
    for (final listing in state.myListings) {
      if (listing.serverId == serverId &&
          Server.sameUrl(listing.supabaseUrl, supabaseUrl)) {
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
