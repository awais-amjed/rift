import '../enums/report_reason.dart';

/// One person's report of a listing, as a moderator reads it.
///
/// [reportedName] and [reportedDescription] are what the listing said when it
/// was reported. Its owner may have edited it since, and the moderator should
/// still see what the reporter saw.
class ListingReport {
  final String id;
  final DateTime createdAt;
  final ReportReason reason;
  final String? details;
  final String reporterHandle;
  final String? reportedName;
  final String? reportedDescription;

  const ListingReport({
    required this.id,
    required this.createdAt,
    required this.reason,
    this.details,
    required this.reporterHandle,
    this.reportedName,
    this.reportedDescription,
  });

  factory ListingReport.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'] as Map<String, dynamic>? ?? const {};
    return ListingReport(
      id: json['id'] as String,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      reason: ReportReason.fromString(json['reason'] as String? ?? ''),
      details: json['details'] as String?,
      reporterHandle: json['reporter_handle'] as String? ?? '',
      reportedName: snapshot['name'] as String?,
      reportedDescription: snapshot['description'] as String?,
    );
  }
}
