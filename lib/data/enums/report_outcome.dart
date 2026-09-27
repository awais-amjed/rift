/// What was done about a report (`report_outcome`). The server checks each
/// one happened before it records it.
enum ReportOutcome {
  dismissed,
  deleted,
  timedOut,
  banned;

  static ReportOutcome? fromString(String? value) => switch (value) {
    'dismissed' => ReportOutcome.dismissed,
    'deleted' => ReportOutcome.deleted,
    'timed_out' => ReportOutcome.timedOut,
    'banned' => ReportOutcome.banned,
    _ => null,
  };

  String toJson() => switch (this) {
    ReportOutcome.timedOut => 'timed_out',
    _ => name,
  };

  String get label => switch (this) {
    ReportOutcome.dismissed => 'Dismissed',
    ReportOutcome.deleted => 'Message deleted',
    ReportOutcome.timedOut => 'Timed out',
    ReportOutcome.banned => 'Banned',
  };
}
