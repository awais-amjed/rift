/// Where DPDFNet runs in a call, a beta option for testers to compare by
/// ear: friends heard crackle and cut-outs on beta.9, where it runs on its
/// own thread at [normal] (`CALLS.md`, *Rift beside a game*).
///
/// [timeCritical] puts it back on libwebrtc's capture thread, as before
/// beta.5, which a game feels; the other three keep its own thread at that
/// priority. Linux offers only [timeCritical] and [normal] ([offered]).
enum NoiseFilterPriority {
  timeCritical,
  highest,
  aboveNormal,
  normal;

  String get label => switch (this) {
    timeCritical => 'Time critical',
    highest => 'Highest',
    aboveNormal => 'Above normal',
    normal => 'Normal',
  };

  /// The choices a computer has. Linux runs no thread above normal for an
  /// ordinary user, so there only the capture thread is another choice, and
  /// its capture thread is no more than normal either.
  static List<NoiseFilterPriority> offered({required bool windows}) =>
      windows ? values : const [timeCritical, normal];

  static NoiseFilterPriority fromJson(Object? value) => switch (value) {
    String name => values.asNameMap()[name] ?? normal,
    _ => normal,
  };

  String toJson() => name;
}
