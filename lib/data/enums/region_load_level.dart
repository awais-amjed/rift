/// How busy a voice region is, as `voice_roster` reports it.
///
/// A level rather than a count because the server takes it over every room on
/// the node — private channels included, and other servers' calls on a shared
/// LiveKit — and a count from that told any member when a call they could not
/// see had started. There is no `idle` for the same reason: see
/// `voice_roster/index.ts`.
///
/// Declared quietest first, so [index] orders them.
enum RegionLoadLevel {
  low,
  medium,
  high;

  /// Null for anything unknown, including the null an unreachable region
  /// reports.
  static RegionLoadLevel? tryParse(Object? value) => switch (value) {
    'low' => RegionLoadLevel.low,
    'medium' => RegionLoadLevel.medium,
    'high' => RegionLoadLevel.high,
    _ => null,
  };

  String toJson() => name;

  /// How a picker row says it.
  String get label => '$name load';
}
