import 'listing_report.dart';
import 'moderation_listing.dart';

/// One entry in the moderation queue: a listing and every open report of it.
///
/// Grouped by listing because that is what a moderator decides on — ten
/// reports of one server are one decision, not ten.
class ModerationCase {
  final ModerationListing listing;
  final List<ListingReport> reports;

  const ModerationCase({required this.listing, required this.reports});

  /// Whether the listing changed after it was first reported — the moderator
  /// is then looking at something the reporters never saw.
  bool get editedSinceReport {
    final first = reports.isEmpty ? null : reports.last;
    if (first == null) return false;
    return (first.reportedName ?? listing.name) != listing.name ||
        (first.reportedDescription ?? '') != (listing.description ?? '');
  }

  factory ModerationCase.fromJson(Map<String, dynamic> json) {
    return ModerationCase(
      listing: ModerationListing.fromJson(
        json['listing'] as Map<String, dynamic>,
      ),
      reports: [
        for (final r in json['reports'] as List<dynamic>? ?? const [])
          ListingReport.fromJson(r as Map<String, dynamic>),
      ],
    );
  }
}
