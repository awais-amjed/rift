/// What asking a server to let us go came to.
enum LeaveOutcome {
  /// The server took us off its list.
  left,

  /// The server is too old to be asked; forgetting it is all there is.
  unsupported,

  /// The server said no, and we are still on it.
  refused,

  /// The server did not answer, so it may still list us.
  unreachable,
}
