/// Why somebody reported a directory listing — central's
/// `directory_reports.reason`, a fixed list so the moderation queue can say
/// how bad a thing is claimed to be without reading every note.
///
/// In the order the report dialog offers them: the ones a host acts on first.
enum ReportReason {
  illegal,
  sexual,
  violence,
  hate,
  scam,
  spam,
  other;

  /// Anything central sends that this client does not know reads as [other],
  /// so a reason added there later still shows up here.
  static ReportReason fromString(String value) => ReportReason.values
      .firstWhere((r) => r.name == value, orElse: () => ReportReason.other);

  String toJson() => name;

  String get label => switch (this) {
    ReportReason.illegal => 'Illegal content',
    ReportReason.sexual => 'Sexual content',
    ReportReason.violence => 'Violence or threats',
    ReportReason.hate => 'Hate or harassment',
    ReportReason.scam => 'Scam or impersonation',
    ReportReason.spam => 'Spam',
    ReportReason.other => 'Something else',
  };
}
