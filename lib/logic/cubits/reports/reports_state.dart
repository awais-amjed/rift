part of 'reports_cubit.dart';

/// One report, with what this device made of the message it names.
class ReportEntry extends Equatable {
  final MemberReport report;

  /// Null for a report about a member rather than a message.
  final ReportedContent? content;

  /// The reported message as opened — for showing it, and for knowing which
  /// attachments to delete with it. Null when it could not be opened.
  final ChatMessage? message;

  const ReportEntry({required this.report, this.content, this.message});

  @override
  List<Object?> get props => [report, content, message];
}

/// One server's reports, for somebody who may review them.
class ReportsState extends Equatable {
  /// Whose reports these are, or null while there is nothing to review. What
  /// "may I act on this" is asked against, since the page can be about a
  /// server the person is not looking at.
  final String? serverId;

  /// Open reports, newest first.
  final List<ReportEntry> open;

  /// Closed reports, newest first — read only when asked for, since the page
  /// opens on what still needs doing.
  final List<ReportEntry> closed;
  final bool loading;
  final bool closedLoaded;

  /// Whether the member may review reports here at all. False hides the page
  /// and the badge.
  final bool canReview;
  final String? error;

  const ReportsState({
    this.serverId,
    this.open = const [],
    this.closed = const [],
    this.loading = false,
    this.closedLoaded = false,
    this.canReview = false,
    this.error,
  });

  int get openCount => open.length;

  ReportsState copyWith({
    List<ReportEntry>? open,
    List<ReportEntry>? closed,
    bool? loading,
    bool? closedLoaded,
    bool? canReview,
    String? error,
    bool clearError = false,
  }) => ReportsState(
    serverId: serverId,
    open: open ?? this.open,
    closed: closed ?? this.closed,
    loading: loading ?? this.loading,
    closedLoaded: closedLoaded ?? this.closedLoaded,
    canReview: canReview ?? this.canReview,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  List<Object?> get props => [
    serverId,
    open,
    closed,
    loading,
    closedLoaded,
    canReview,
    error,
  ];
}
