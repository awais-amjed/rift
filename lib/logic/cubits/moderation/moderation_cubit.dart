import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/classes/api_response.dart';
import '../../../data/classes/moderation_case.dart';
import '../../../data/classes/moderation_listing.dart';
import '../../../data/classes/publisher_ban.dart';
import '../../../data/enums/listing_kind.dart';
import '../../../data/enums/report_reason.dart';
import '../../../data/repositories/directory_moderation_repository.dart';

part 'moderation_state.dart';

/// Reporting directory listings, and — for the accounts central lists as
/// moderators — the queue, what is hidden, and who is banned.
///
/// Ephemeral and lazy, like the directory cubits: nothing here is worth
/// keeping between launches, and an account that never opens settings or the
/// directory never asks central whether it moderates.
///
/// Nothing is applied before central answers. Every action reloads the lists
/// it changed, so what the page shows is always what central holds.
class ModerationCubit extends Cubit<ModerationState> {
  final DirectoryModerationRepository _repo;

  ModerationCubit({DirectoryModerationRepository? repo})
    : _repo = repo ?? DirectoryModerationRepository(),
      super(const ModerationState());

  /// The signed-in central account, so a listing's owner is not offered a
  /// Report item on their own.
  String? get currentUserId => _repo.currentUserId;

  // ── Role ──────────────────────────────────────────────────

  /// Ask central whether this account moderates. Called when settings or
  /// the directory opens, and when the central sign-in changes. A failure
  /// reads as "no": the page stays hidden until central says otherwise.
  Future<void> checkRole() async {
    final response = await _repo.isModerator();
    if (isClosed) return;
    final isModerator = response.success && response.data == true;
    if (isModerator == state.isModerator) return;
    // A change of account must not leave the last one's queue on screen.
    emit(ModerationState(isModerator: isModerator));
  }

  // ── Reporting ─────────────────────────────────────────────

  /// Report a listing. Handed back rather than emitted, because the dialog
  /// that asked is the one place that says whether it worked.
  Future<APIResponse> report({
    required ListingKind kind,
    required String listingId,
    required ReportReason reason,
    String? details,
  }) => _repo.report(
    kind: kind,
    listingId: listingId,
    reason: reason,
    details: details,
  );

  // ── Reading ───────────────────────────────────────────────

  /// All three lists at once: they change together, since hiding closes a
  /// report and a ban hides listings.
  Future<void> load() async {
    if (!state.isModerator) return;
    emit(state.copyWith(loading: true, clearError: true));

    final results = await Future.wait([
      _repo.queue(),
      _repo.hidden(),
      _repo.bans(),
    ]);
    if (isClosed) return;

    final failed = results.where((r) => !r.success).firstOrNull;
    emit(
      state.copyWith(
        loading: false,
        hasLoaded: true,
        queue: results[0].success
            ? results[0].data as List<ModerationCase>
            : null,
        hidden: results[1].success
            ? results[1].data as List<ModerationListing>
            : null,
        bans: results[2].success ? results[2].data as List<PublisherBan> : null,
        error: failed?.error,
        clearError: failed == null,
      ),
    );
  }

  // ── Acting ────────────────────────────────────────────────

  /// Take a listing out of the directory. [reason] is shown to its owner.
  Future<APIResponse> hide(ModerationListing listing, {String? reason}) =>
      hideById(listing.kind, listing.id, reason: reason);

  /// [hide] from a place that holds a directory row rather than a moderation
  /// one — a moderator hiding something straight from the browser.
  Future<APIResponse> hideById(
    ListingKind kind,
    String listingId, {
    String? reason,
  }) => _act(
    listingId,
    () => _repo.setHidden(
      kind: kind,
      listingId: listingId,
      hidden: true,
      reason: reason,
    ),
  );

  /// Put a hidden listing back in the directory.
  Future<APIResponse> unhide(ModerationListing listing) => _act(
    listing.id,
    () => _repo.setHidden(
      kind: listing.kind,
      listingId: listing.id,
      hidden: false,
    ),
  );

  /// Leave a listing up and close its reports.
  Future<APIResponse> dismiss(ModerationListing listing) => _act(
    listing.id,
    () => _repo.dismiss(kind: listing.kind, listingId: listing.id),
  );

  /// Stop an account publishing. Everything it has listed is hidden with it.
  Future<APIResponse> ban(String userId, {String? reason}) => _act(
    userId,
    () => _repo.setBanned(userId: userId, banned: true, reason: reason),
  );

  /// Let an account publish again. Its listings stay hidden until each is
  /// shown again by hand.
  Future<APIResponse> unban(String userId) =>
      _act(userId, () => _repo.setBanned(userId: userId, banned: false));

  /// Run one action with [id] marked busy, then reload what it changed.
  Future<APIResponse> _act(
    String id,
    Future<APIResponse> Function() action,
  ) async {
    emit(state.copyWith(busy: {...state.busy, id}));
    final response = await action();
    if (isClosed) return response;
    emit(state.copyWith(busy: {...state.busy}..remove(id)));
    if (response.success) await load();
    return response;
  }
}
