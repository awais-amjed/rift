/// Transforms on the shape every per-server tally uses: `serverId → (id → T)`.
///
/// Pulled out of [NotificationsState] because the transforms are the part with
/// an invariant worth testing on its own — **a zero count is an absent key, and
/// an empty inner map is an absent server** — and because the same nesting now
/// holds three different things (unread counts, channel levels, DM levels).
/// Three copies of "copy the outer, copy the inner, prune if it emptied" is
/// where one of them quietly stops pruning.
///
/// Every method returns a new map; nothing here mutates what it is given.
class PerServerMap {
  const PerServerMap._();

  /// One server's inner map replaced wholesale — what a re-seed produces. An
  /// empty replacement removes the server rather than storing an empty map.
  static Map<String, Map<String, T>> replaced<T>(
    Map<String, Map<String, T>> outer,
    String serverId,
    Map<String, T> values,
  ) {
    final next = Map.of(outer);
    if (values.isEmpty) {
      next.remove(serverId);
    } else {
      next[serverId] = Map.unmodifiable(values);
    }
    return next;
  }

  /// One entry set, creating the server's inner map if it had none.
  static Map<String, Map<String, T>> withEntry<T>(
    Map<String, Map<String, T>> outer,
    String serverId,
    String key,
    T value,
  ) {
    final inner = Map<String, T>.from(outer[serverId] ?? const {})
      ..[key] = value;
    return Map.of(outer)..[serverId] = inner;
  }

  /// One count raised by one.
  static Map<String, Map<String, int>> incremented(
    Map<String, Map<String, int>> outer,
    String serverId,
    String key,
  ) => withEntry(outer, serverId, key, (outer[serverId]?[key] ?? 0) + 1);

  /// One entry removed, or **null when there was nothing to remove** — so a
  /// caller can hand back the same state instance rather than emitting a state
  /// identical to the one before it.
  static Map<String, Map<String, T>>? without<T>(
    Map<String, Map<String, T>> outer,
    String serverId,
    String key,
  ) {
    final inner = outer[serverId];
    if (inner == null || !inner.containsKey(key)) return null;
    final updated = Map<String, T>.from(inner)..remove(key);
    final next = Map.of(outer);
    if (updated.isEmpty) {
      next.remove(serverId);
    } else {
      next[serverId] = updated;
    }
    return next;
  }
}
