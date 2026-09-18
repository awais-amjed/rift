/// Running the same refresh at most twice over, however many ask for it.
///
/// A client is told the same thing several ways on purpose. One structural
/// change on a server arrives as a database announcement and as the doorbell
/// somebody rang, and the member who made the change re-reads straight after
/// their own write. Three round trips, three identical answers, and nothing
/// in between them that could have changed.
///
/// The naive fix — drop a request while one is in flight — is wrong in a way
/// that only shows up later: the answer already on its way was asked for
/// before the new caller's reason to ask existed, so handing it back leaves
/// the client one change behind, and it stays behind until something else
/// happens to ask again.
///
/// So a caller arriving mid-flight waits for the running read to land and
/// then takes one more turn. Everybody who arrives in that window shares that
/// turn, because they all want the same thing and one read answers all of
/// them. At most two reads are ever outstanding, and every caller is
/// guaranteed an answer fetched after they asked.
///
/// The work must be idempotent and must not depend on who asked — this hands
/// one caller's result to another by design.
class CoalescedRefresh<T> {
  final Future<T> Function() _read;

  /// The read running now, and the one promised to everyone waiting on it.
  Future<T>? _inFlight;
  Future<T>? _queued;

  CoalescedRefresh(this._read);

  /// Whether a read is running right now. For tests and diagnostics.
  bool get isRunning => _inFlight != null;

  Future<T> call() {
    final inFlight = _inFlight;
    if (inFlight == null) return _start();
    return _queued ??= _after(inFlight);
  }

  Future<T> _after(Future<T> inFlight) async {
    // Whether it worked is the running caller's business, not ours. Chained
    // with a plain `then` a failure would skip our turn entirely and leave
    // the queue slot holding the dead future, which every later caller would
    // then be handed — the refresh dead for good, quietly.
    try {
      await inFlight;
    } catch (_) {
      // Ours is a fresh read either way.
    }
    // Cleared before the read rather than after it: somebody arriving while
    // *this* one is in flight is asking about something it may not have
    // seen, and is owed a turn of their own.
    _queued = null;
    return _start();
  }

  Future<T> _start() {
    final read = _read();
    _inFlight = read;
    return read.whenComplete(() {
      if (identical(_inFlight, read)) _inFlight = null;
    });
  }
}
