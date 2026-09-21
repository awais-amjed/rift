/// Combining this device's server list with the one already in the cloud.
///
/// Pure, and out of the cubit, for the same reason [ServerImportMerge] is:
/// the failure mode of a wrong clause here is a silently shorter list, not an
/// exception. The two are not the same rule, though, and the difference is
/// the whole point:
///
/// - [ServerImportMerge] is **restore**. The backup is the truth and the
///   device is replaced by it, because the user asked for exactly that.
/// - [BackupMerge] is **sync**. Neither side is the truth. A device uploads
///   what it knows *combined with* what is already up there, because the
///   other copy may hold a server this one has never seen — and overwriting
///   it with a blind upsert is how joining a server on a phone disappears
///   the moment the laptop's next auto-backup lands.
///
/// Union on the list, last-writer-wins on the order. Those are different
/// rules because they answer different questions: a server is a fact (it
/// exists or it does not) while an order is an opinion (the most recent one
/// wins, and there is nothing to preserve from the older).
library;

/// The servers half of a backup: the list, in rail order, and the clock that
/// says how recently somebody chose that order.
class ServerManifest {
  /// Bumped when the *shape* changes, which is not the same as [orderClock].
  static const int version = 2;

  /// Rail order. The array's order is the user's order — there is no rank
  /// column, because a list already has one and two of them can disagree.
  final List<Map<String, dynamic>> servers;

  /// A Lamport counter, deliberately not a timestamp.
  ///
  /// A merge adopts the higher of the two and a reorder adds one, so a
  /// device's clock is always the highest it has ever seen and the reorder
  /// made *after* learning of another one always outranks it. Wall time
  /// would be the obvious choice and the wrong one: a phone ninety seconds
  /// ahead of a laptop would win every tie for ninety seconds, including
  /// the ties it should lose.
  final int orderClock;

  const ServerManifest({required this.servers, this.orderClock = 0});

  static const ServerManifest empty = ServerManifest(servers: []);

  /// Reads either shape.
  ///
  /// v1 wrote a bare JSON array with no clock, so one reads as 0 and loses
  /// every tie — which is right, since a backup written before ordering
  /// existed holds no opinion about order to defend.
  factory ServerManifest.decode(Object? json) {
    if (json is List) {
      return ServerManifest(servers: _entries(json));
    }
    if (json is Map<String, dynamic>) {
      return ServerManifest(
        servers: _entries(json['servers']),
        orderClock: (json['order_clock'] as num?)?.toInt() ?? 0,
      );
    }
    return empty;
  }

  Map<String, dynamic> encode() => {
    'v': version,
    'servers': servers,
    'order_clock': orderClock,
  };

  static List<Map<String, dynamic>> _entries(Object? raw) => raw is List
      ? [
          for (final entry in raw)
            if (entry is Map<String, dynamic>) entry,
        ]
      : const [];
}

class BackupMerge {
  const BackupMerge._();

  /// What should be uploaded, given what this device holds ([mine]) and what
  /// is already in the cloud ([theirs]).
  ///
  /// Every server either side knows survives. The order comes from whichever
  /// side last chose one; the metadata comes from [mine], because this device
  /// has been talking to these servers and the other copy may be months stale
  /// — except field by field, so a stub from a fresh restore cannot blank an
  /// icon the cloud copy still remembers.
  static ServerManifest union({
    required ServerManifest mine,
    required ServerManifest theirs,
  }) {
    // A tie goes to the writer. Two devices that have each reordered once
    // have equal claims, and picking the one doing the uploading at least
    // matches what the person in front of it just did.
    final mineLeads = mine.orderClock >= theirs.orderClock;
    final leader = mineLeads ? mine.servers : theirs.servers;
    final follower = mineLeads ? theirs.servers : mine.servers;

    final merged = <String, Map<String, dynamic>>{};
    for (final entry in theirs.servers) {
      final key = _key(entry);
      if (key != null) merged[key] = entry;
    }
    for (final entry in mine.servers) {
      final key = _key(entry);
      if (key != null) merged[key] = _prefer(entry, merged[key]);
    }

    final ordered = <Map<String, dynamic>>[];
    final placed = <String>{};
    for (final list in [leader, follower]) {
      for (final entry in list) {
        final key = _key(entry);
        if (key == null || !placed.add(key)) continue;
        ordered.add(merged[key]!);
      }
    }

    return ServerManifest(
      servers: _withoutShadowedHosts(ordered),
      orderClock: mine.orderClock > theirs.orderClock
          ? mine.orderClock
          : theirs.orderClock,
    );
  }

  /// [mine] with any field it does not have filled in from [theirs].
  ///
  /// A device restoring onto a fresh install holds stubs — id, name, url and
  /// nothing else, because the rest arrives with `get_server_details` on
  /// first selection. Uploading those stubs as-is would push the gaps into
  /// the cloud copy and from there onto every other device.
  static Map<String, dynamic> _prefer(
    Map<String, dynamic> mine,
    Map<String, dynamic>? theirs,
  ) {
    if (theirs == null) return mine;
    final out = Map<String, dynamic>.from(theirs);
    for (final field in mine.entries) {
      if (field.value != null) out[field.key] = field.value;
    }
    return out;
  }

  /// Drops a v1 host record once a real server on that host is present.
  ///
  /// v1 backups recorded *projects*, not servers, so an entry can arrive with
  /// a url and no id. Kept beside the real servers on the same host it would
  /// restore as a nameless stub that belongs to nobody; kept on its own it is
  /// still the only record that the identity ever joined that project.
  static List<Map<String, dynamic>> _withoutShadowedHosts(
    List<Map<String, dynamic>> servers,
  ) {
    final identified = <String>{
      for (final entry in servers)
        if (entry['id'] != null) (entry['supabaseUrl'] as String?) ?? '',
    };
    return [
      for (final entry in servers)
        if (entry['id'] != null ||
            !identified.contains((entry['supabaseUrl'] as String?) ?? ''))
          entry,
    ];
  }

  /// `(supabaseUrl, id)`, never the URL alone — one Supabase project hosts as
  /// many servers as its operator wants. Null for an entry with no URL, which
  /// is not a server anybody can reach.
  static String? _key(Map<String, dynamic> entry) {
    final url = (entry['supabaseUrl'] as String?) ?? '';
    if (url.isEmpty) return null;
    // `\u0000` because a URL cannot contain a NUL, so no two distinct
    // servers can collide into one key.
    return '$url\u0000${(entry['id'] as String?) ?? ''}';
  }
}
