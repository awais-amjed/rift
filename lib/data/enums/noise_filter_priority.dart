/// Where DPDFNet runs in a call on Windows, a beta option for testers to
/// compare by ear: friends heard crackle and cut-outs on beta.9, where it
/// runs on its own thread at [normal] (`CALLS.md`, *Rift beside a game*).
///
/// [timeCritical] puts it back on libwebrtc's capture thread, as before
/// beta.5, which a game feels; the other three keep its own thread at that
/// priority.
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

  static NoiseFilterPriority fromJson(Object? value) => switch (value) {
    String name => values.asNameMap()[name] ?? normal,
    _ => normal,
  };

  String toJson() => name;
}
