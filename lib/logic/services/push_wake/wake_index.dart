import 'dart:convert';
import 'dart:io';

import '../storage_namespace.dart';

/// One joined server, as much of it as waking up needs.
class WakeServer {
  final String id;
  final String name;
  final String supabaseUrl;
  final String anonKey;

  /// This device's user id on that server. `users.id` is the GoTrue uid, so it
  /// is also what a read cursor and a keyring entry are keyed by.
  final String userId;

  /// This device's username there, so the isolate can tell being *named* in a
  /// channel from being in the room — the one distinction a notification about
  /// a busy channel actually turns on.
  final String username;

  /// The Ed25519 derivation version, so the isolate signs in as the same
  /// identity a rotated key left behind.
  final String keyVersion;

  /// Channel id → name, for saying "#general" rather than a uuid.
  final Map<String, String> channels;

  const WakeServer({
    required this.id,
    required this.name,
    required this.supabaseUrl,
    required this.anonKey,
    required this.userId,
    required this.username,
    required this.keyVersion,
    required this.channels,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': supabaseUrl,
    'key': anonKey,
    'user': userId,
    'username': username,
    'version': keyVersion,
    'channels': channels,
  };

  static WakeServer? fromJson(Map<String, dynamic> json) {
    final id = json['id'], url = json['url'], user = json['user'];
    if (id is! String || url is! String || user is! String) return null;
    return WakeServer(
      id: id,
      name: json['name'] as String? ?? 'Rift',
      supabaseUrl: url,
      anonKey: json['key'] as String? ?? '',
      userId: user,
      username: json['username'] as String? ?? '',
      keyVersion: json['version'] as String? ?? 'v1',
      channels:
          (json['channels'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
          const {},
    );
  }

  /// Whether two snapshots say the same thing. The index is rewritten from
  /// every server-list change, and most of those — a token refresh, a
  /// selection — change nothing the isolate reads.
  bool sameAs(WakeServer other) =>
      id == other.id &&
      name == other.name &&
      supabaseUrl == other.supabaseUrl &&
      anonKey == other.anonKey &&
      userId == other.userId &&
      username == other.username &&
      keyVersion == other.keyVersion &&
      channels.length == other.channels.length &&
      channels.entries.every((e) => other.channels[e.key] == e.value);
}

/// What the app leaves behind for the push background isolate to find.
///
/// The isolate is woken into a process with none of the app's state: no
/// cubits, no hydrated storage, nothing that was in memory a moment ago. It
/// still needs to know which servers this device is on before it can ask any
/// of them what arrived.
///
/// A file of its own rather than a read of the app's hydrated state, for two
/// reasons. The isolate can be alive while the app still is — Android runs the
/// handler beside a backgrounded process — and two Hive instances on one box
/// is a lock, not a read. And the isolate needs a handful of fields out of a
/// large serialized cubit whose shape is free to change; a purpose-built
/// snapshot cannot be broken by refactoring the state class.
///
/// Written atomically, because the reader is another isolate and a half-written
/// file is worse than a stale one.
class WakeIndex {
  final List<WakeServer> servers;

  const WakeIndex({this.servers = const []});

  static const _fileName = 'push_wake.json';

  static Future<File> _file() async {
    final dir = await StorageNamespace.profileDirectory(
      StorageNamespace.apply(),
    );
    await Directory(dir).create(recursive: true);
    return File('$dir/$_fileName');
  }

  /// The snapshot, or an empty one if there is none — a device that has never
  /// joined a server, or one where writing failed. Never throws: a wake that
  /// cannot read the index still posts the notification it can.
  static Future<WakeIndex> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const WakeIndex();
      final json = jsonDecode(await file.readAsString());
      final list = (json is Map ? json['servers'] : null) as List? ?? const [];
      return WakeIndex(
        servers: list
            .whereType<Map>()
            .map((e) => WakeServer.fromJson(e.cast<String, dynamic>()))
            .whereType<WakeServer>()
            .toList(),
      );
    } catch (_) {
      return const WakeIndex();
    }
  }

  /// Replace the snapshot. Written to a sibling and renamed over the top, so a
  /// reader either sees the whole of the old file or the whole of the new one.
  static Future<void> write(WakeIndex index) async {
    try {
      final file = await _file();
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'servers': index.servers.map((s) => s.toJson()).toList()}),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      // Best-effort. A missing index costs richer notifications, nothing else.
    }
  }

  bool sameAs(WakeIndex other) =>
      servers.length == other.servers.length &&
      List.generate(
        servers.length,
        (i) => servers[i].sameAs(other.servers[i]),
      ).every((same) => same);
}

/// Keeping the wake index in step with the app's server list.
///
/// The app is the only thing that knows which servers this device is on, and
/// the isolate cannot ask it — it is woken into a process that shares nothing.
/// So the app leaves a snapshot behind, and this decides when it is worth
/// rewriting: the server list changes on every token refresh and every
/// selection, and almost none of those change anything the isolate reads.
class WakeIndexWriter {
  WakeIndex _last = const WakeIndex();
  bool _primed = false;

  Future<void> update(WakeIndex next) async {
    if (_primed && _last.sameAs(next)) return;
    _primed = true;
    _last = next;
    await WakeIndex.write(next);
  }
}
