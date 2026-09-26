import 'package:supabase_flutter/supabase_flutter.dart';

import '../classes/api_response.dart';
import '../enums/listing_kind.dart';
import '../enums/report_reason.dart';

/// Reporting a directory listing to Rift's moderators — central's
/// `report_listing`.
///
/// The only part of moderation the app holds. Moderators work on their own
/// site with their own accounts, so nothing here reads a report back or acts
/// on one.
class ListingReportRepository {
  SupabaseClient get _client => Supabase.instance.client;

  /// Report a listing. Reporting it again while the first is still open
  /// replaces the first.
  Future<APIResponse> report({
    required ListingKind kind,
    required String listingId,
    required ReportReason reason,
    String? details,
  }) async {
    try {
      await _client.rpc(
        'report_listing',
        params: {
          'p_kind': kind.toJson(),
          'p_listing': listingId,
          'p_reason': reason.toJson(),
          'p_details': details,
        },
      );
      return APIResponse.success(null);
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
  };
}
