import 'package:supabase_flutter/supabase_flutter.dart';

import '../classes/api_response.dart';
import '../classes/moderation_case.dart';
import '../classes/moderation_listing.dart';
import '../classes/publisher_ban.dart';
import '../enums/listing_kind.dart';
import '../enums/report_reason.dart';

/// Reporting directory listings, and the moderators' side of it — central's
/// `report_listing` and `moderation_*` functions.
///
/// Every call is an RPC. None of the three tables behind them has a grant, so
/// there is nothing to read directly, and each moderation function refuses
/// anyone central does not list as a moderator. Nothing the app draws decides
/// who may moderate; it only decides whether to show the page.
class DirectoryModerationRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// The signed-in central account, or null. A listing's own publisher gets
  /// no Report item on it: the way to take your own listing down is to
  /// delete it.
  String? get currentUserId => _client.auth.currentUser?.id;

  /// Report a listing. Reporting it again while the first is still open
  /// replaces the first.
  Future<APIResponse> report({
    required ListingKind kind,
    required String listingId,
    required ReportReason reason,
    String? details,
  }) => _call(
    'report_listing',
    params: {
      'p_kind': kind.toJson(),
      'p_listing': listingId,
      'p_reason': reason.toJson(),
      'p_details': details,
    },
  );

  /// Whether this account moderates the directory. False, without asking,
  /// when nobody is signed in.
  Future<APIResponse> isModerator() async {
    if (currentUserId == null) return APIResponse.success(false);
    final response = await _call('is_central_admin');
    return response.success
        ? APIResponse.success(response.data == true)
        : response;
  }

  /// Every listing with an open report, most-reported first.
  Future<APIResponse> queue() async {
    final response = await _call('moderation_queue');
    if (!response.success) return response;
    return APIResponse.success([
      for (final c in response.data as List<dynamic>)
        ModerationCase.fromJson(c as Map<String, dynamic>),
    ]);
  }

  /// What is hidden now, newest first.
  Future<APIResponse> hidden() async {
    final response = await _call('moderation_hidden');
    if (!response.success) return response;
    return APIResponse.success([
      for (final l in response.data as List<dynamic>)
        ModerationListing.fromJson(l as Map<String, dynamic>),
    ]);
  }

  /// Accounts that may not publish, newest first.
  Future<APIResponse> bans() async {
    final response = await _call('moderation_bans');
    if (!response.success) return response;
    return APIResponse.success([
      for (final b in response.data as List<dynamic>)
        PublisherBan.fromJson(b as Map<String, dynamic>),
    ]);
  }

  /// Hide a listing — which also closes its reports and drops its icon — or
  /// show it again. [reason] is shown to the owner.
  Future<APIResponse> setHidden({
    required ListingKind kind,
    required String listingId,
    required bool hidden,
    String? reason,
  }) => _call(
    'moderation_set_hidden',
    params: {
      'p_kind': kind.toJson(),
      'p_listing': listingId,
      'p_hidden': hidden,
      'p_reason': reason,
    },
  );

  /// Close a listing's reports and leave it up.
  Future<APIResponse> dismiss({
    required ListingKind kind,
    required String listingId,
  }) => _call(
    'moderation_dismiss',
    params: {'p_kind': kind.toJson(), 'p_listing': listingId},
  );

  /// Stop an account publishing (which hides all it has listed), or let it
  /// again (which brings nothing back).
  Future<APIResponse> setBanned({
    required String userId,
    required bool banned,
    String? reason,
  }) => _call(
    'moderation_set_banned',
    params: {'p_user': userId, 'p_banned': banned, 'p_reason': reason},
  );

  Future<APIResponse> _call(
    String function, {
    Map<String, dynamic>? params,
  }) async {
    try {
      return APIResponse.success(await _client.rpc(function, params: params));
    } on PostgrestException catch (e) {
      final identifier = e.message.trim();
      return APIResponse.error(
        _messages[identifier] ?? e.message,
        errorCode: identifier,
      );
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  // ── Errors ────────────────────────────────────────────────
  // Central raises bare identifiers; these are the ones a person can act on.

  static const _messages = {
    'reporter_has_no_profile':
        'Claim a handle on your Rift account before reporting a listing.',
    'listing_not_found': 'That listing is no longer in the directory.',
    'cannot_report_own_listing':
        'This is your own listing. Remove it instead of reporting it.',
    'report_limit_reached':
        'You have sent as many reports as one account may in a day. Try '
        'again tomorrow.',
    'not_a_moderator': 'Only Rift moderators can do that.',
    'cannot_ban_a_moderator': 'A moderator cannot be banned from here.',
    'user_not_found': 'That account no longer exists.',
  };
}
