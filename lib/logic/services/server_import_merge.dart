import '../../data/classes/server.dart';

/// Reconciling the device's server list against a restored vault backup.
///
/// Pure, and out of the cubit, because the rule it encodes is the kind that
/// is only ever wrong in one clause — and the wrong clause here does not
/// throw, it silently drops servers.
///
/// **A server is identified by `(supabaseUrl, id)`, never by URL alone.** One
/// Supabase project hosts as many servers as its operator wants, which is why
/// the chat identity is scoped to `(host, serverId)` and why central reserves
/// that pair rather than a bare URL. Matching on the URL made every server on
/// a project collapse into whichever one the lookup happened to hold: a
/// device that knew three servers on one host, restoring a backup that held
/// those same three, came out with three copies of one of them and the other
/// two gone from the list.
class ServerImportMerge {
  const ServerImportMerge._();

  /// The epoch, which is what a restored token is stamped with: the identity
  /// changed under it, so the next selection must re-authenticate rather than
  /// trust what is in hand.
  static final DateTime stale = DateTime.fromMillisecondsSinceEpoch(0);

  /// The list a device should hold after importing [imported].
  ///
  /// Order follows the backup, which is the order the rail had at export.
  /// Servers the backup does not mention are dropped — a backup is the whole
  /// truth about which servers an identity has joined.
  static List<Server> apply({
    required List<Server> existing,
    required List<Map<String, dynamic>> imported,
  }) {
    final restored = <Server>[];
    final taken = <String>{};

    // One row per id, which is all the rest of the app tells servers apart
    // by: a second under the same id had the first one's token and socket.
    void keep(Server server) {
      if (taken.add(server.id)) restored.add(server);
    }

    // The token in hand was minted for whoever this device was before the
    // restore, which may be another identity: blanked, so no call goes out
    // as them while the new identity signs in (stamped stale, the first call
    // signs in again).
    Server restoredFrom(Server known, String keyVersion) => known
        .copyWith(token: '', keyVersion: keyVersion)
        .copyWith(tokenIssuedAt: stale);

    for (final meta in imported) {
      final url = (meta['supabaseUrl'] as String?) ?? '';
      if (url.isEmpty) continue;
      final keyVersion = (meta['keyVersion'] as String?) ?? 'v1';
      final id = meta['id'] as String?;

      // A v1 backup recorded *hosts*, not servers — see `joined_servers` in
      // the vault blob. So it says "this identity has joined this project"
      // and nothing about which servers on it, and the honest reading is to
      // keep every one this device already knows there. Picking one and
      // discarding its neighbours is what the URL match used to do.
      // It recorded them as bare hosts, so a server here is matched by its
      // URL's host: compared whole, every one was dropped.
      if (id == null) {
        for (final server in existing) {
          if (server.supabaseUrl == url ||
              Uri.tryParse(server.supabaseUrl)?.host == url) {
            keep(restoredFrom(server, keyVersion));
          }
        }
        continue;
      }

      final known = _find(existing, url, id);
      keep(
        (known == null ? null : restoredFrom(known, keyVersion)) ??
            // Nothing here knows it — a fresh device. What the backup carries
            // is enough to draw the rail and to log in; the rest arrives with
            // `get_server_details` on first selection.
            Server(
              id: id,
              name: (meta['name'] as String?) ?? 'Server',
              iconPath: meta['iconUrl'] as String?,
              supabaseUrl: url,
              supabaseKey: meta['supabaseKey'] as String?,
              livekitUrl: meta['livekitUrl'] as String?,
              token: '',
              keyVersion: keyVersion,
              tokenIssuedAt: stale,
            ),
      );
    }
    return restored;
  }

  /// The same list with any server that appears more than once removed,
  /// keeping the first.
  ///
  /// Applied when the persisted state is read back, so a device left holding
  /// duplicates by the URL match above heals on its next launch instead of
  /// showing the same server in the rail forever. It cannot be undone from
  /// the UI: every write path maps by id and so updates all the copies at
  /// once, and leaving removes all of them together.
  ///
  /// By id alone, as the rest of the app finds a server: two rows with one
  /// id, at two addresses, shared one token and one socket.
  static List<Server> deduplicate(List<Server> servers) {
    final taken = <String>{};
    return [
      for (final server in servers)
        if (taken.add(server.id)) server,
    ];
  }

  static Server? _find(List<Server> servers, String url, String id) {
    for (final server in servers) {
      if (server.supabaseUrl == url && server.id == id) return server;
    }
    return null;
  }
}
