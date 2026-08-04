/// Which surface the centre pane is showing.
///
/// One enum rather than a flag per surface, because these are mutually
/// exclusive by nature: the DM tiers are deliberately separate — central DMs
/// belong to your account and follow you between servers, server DMs belong
/// to one server — and a pair of booleans would let both be open at once,
/// which has no meaning.
enum HomeSurface {
  /// A text channel, a voice stage, or the empty state — whatever the
  /// selected server has open.
  server,

  /// Central-account DMs, reached from Home on the rail.
  centralDms,

  /// DMs inside the selected server, reached from its channel column.
  serverDms;

  bool get isDms => this != HomeSurface.server;
}
