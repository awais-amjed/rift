/// Reading the body of a Realtime broadcast.
///
/// What a broadcast callback receives is the delivered *message*, not the
/// payload that was sent: the sender's keys arrive alongside `event` and `type`
/// rather than under them. That is the shape the server sends today, but the
/// client has historically handed over the nested form as well, and the two are
/// impossible to tell apart at a glance — a handler reading the wrong one gets
/// null for every field and silently does nothing, which looks exactly like a
/// broadcast that never arrived.
///
/// So every handler reads through here instead of guessing.
class BroadcastPayload {
  const BroadcastPayload._();

  /// The sent payload, whether it arrived flattened or nested.
  static Map<String, dynamic> of(Map<String, dynamic> message) {
    final nested = message['payload'];
    return nested is Map<String, dynamic> ? nested : message;
  }

  /// One string field of the sent payload, or null if it isn't one.
  ///
  /// A number counts, as its digits: a message id is a string when a client
  /// sent it and a JSON number when the database did, and a handler that took
  /// only strings would ignore every database broadcast without a word.
  static String? stringOf(Map<String, dynamic> message, String key) {
    final value = of(message)[key];
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
  }
}
