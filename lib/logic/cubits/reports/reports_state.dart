part of 'reports_cubit.dart';

/// One report, with what this device made of the message it names.
class ReportEntry extends Equatable {
  final MemberReport report;

  /// Null for a report about a member rather than a message.
  final ReportedContent? content;

  /// The reported message as opened — for showing it, and for knowing which
  /// attachments to delete with it. Null when it could not be opened.
  final ChatMessage? message;

  /// The reported poll's question and options, drawn as words.
  final PollBody? poll;

  const ReportEntry({
    required this.report,
    this.content,
    this.message,
    this.poll,
  });

  @override
  List<Object?> get props => [report, content, message, poll];
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
  final bool closedLoading;

  /// A failed read of the closed list, kept apart from [error] so the page
  /// says it only on the tab it is about.
  final String? closedError;

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
    this.closedLoading = false,
    this.closedError,
    this.canReview = false,
    this.error,
  });

  int get openCount => open.length;

  /// Whether there may be more open reports than were read: the list is one
  /// page, newest first, and a full page says no more than that.
  bool get openMayBeMore => open.length >= ServerRepository.reportsPage;

  ReportsState copyWith({
    List<ReportEntry>? open,
    List<ReportEntry>? closed,
    bool? loading,
    bool? closedLoaded,
    bool? closedLoading,
    String? closedError,
    bool clearClosedError = false,
    bool? canReview,
    String? error,
    bool clearError = false,
  }) => ReportsState(
    serverId: serverId,
    open: open ?? this.open,
    closed: closed ?? this.closed,
    loading: loading ?? this.loading,
    closedLoaded: closedLoaded ?? this.closedLoaded,
    closedLoading: closedLoading ?? this.closedLoading,
    closedError: clearClosedError ? null : (closedError ?? this.closedError),
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
    closedLoading,
    closedError,
    canReview,
    error,
  ];
}
