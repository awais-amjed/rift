/// Why a member reported a message or another member on a self-hosted server
/// (`report_reason` in its schema).
///
/// Shorter than the directory's [ReportReason]: that list is for strangers'
/// listings and Rift's moderators, this one for people in the same community
/// and the moderators they chose.
enum MemberReportReason {
  spam,
  harassment,
  explicit,
  other;

  static MemberReportReason fromString(String? value) =>
      MemberReportReason.values.firstWhere(
        (r) => r.name == value,
        orElse: () => MemberReportReason.other,
      );

  String toJson() => name;

  String get label => switch (this) {
    MemberReportReason.spam => 'Spam',
    MemberReportReason.harassment => 'Harassment or hate',
    MemberReportReason.explicit => 'Explicit content',
    MemberReportReason.other => 'Something else',
  };
}
