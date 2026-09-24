import 'dart:async';

import 'package:http/http.dart' as http;

import '../classes/livekit_node.dart';

/// Measures which of a server's LiveKit nodes is nearest, by asking each one.
///
/// **Measured, not guessed from an IP.** A GeoIP lookup needs a database
/// nobody here wants to ship, is wrong behind a VPN, and answers a question
/// about geography when the one that matters is latency — two boxes the same
/// distance away are not the same distance away over the network.
///
/// The answer only ever *suggests*. It is sent with a token request and the
/// server checks it names one of its own nodes; it is ignored outright when
/// the channel is pinned or a call is already up, because a room cannot move
/// once it exists. So a probe that times out, or a device that cannot make
/// the request at all, costs the default node rather than a failure.
class VoiceRegionProbe {
  /// Long enough for a slow intercontinental round trip, short enough that a
  /// dead node does not hold up joining a call. A node that does not answer
  /// in this is not one to hold a call on anyway.
  static const _timeout = Duration(seconds: 3);

  /// How long a measurement stands. Network conditions drift, but not per
  /// call — re-measuring on every join would add a round trip per node to
  /// something the user is waiting on.
  static const _ttl = Duration(minutes: 30);

  final http.Client _client;

  VoiceRegionProbe({http.Client? client}) : _client = client ?? http.Client();

  final Map<String, _Measurement> _cache = {};

  /// Which node answered fastest, or null when none did.
  ///
  /// Cached per server for [_ttl]. The cache also keys on the node list
  /// itself, so adding or removing a node re-measures rather than keeping an
  /// answer about a set that no longer exists.
  Future<String?> nearest(String serverId, List<LiveKitNode> nodes) async {
    if (nodes.length < 2) {
      // One node is not a choice, and none is not a question. Either way the
      // server's own default is the answer, and measuring would be a round
      // trip to learn nothing.
      return null;
    }

    final fingerprint = nodes.map((n) => n.id).join(',');
    final cached = _cache[serverId];
    if (cached != null &&
        cached.fingerprint == fingerprint &&
        DateTime.now().difference(cached.at) < _ttl) {
      return cached.nodeId;
    }

    final results = await Future.wait(nodes.map(_measure));
    final answered = results.where((r) => r != null).cast<_Result>().toList()
      ..sort((a, b) => a.micros.compareTo(b.micros));

    final winner = answered.isEmpty ? null : answered.first.nodeId;
    _cache[serverId] = _Measurement(
      fingerprint: fingerprint,
      nodeId: winner,
      at: DateTime.now(),
    );
    return winner;
  }

  /// Forget what was measured for [serverId], so the next ask re-measures.
  void invalidate(String serverId) => _cache.remove(serverId);

  /// One node's round trip, or null when it did not answer.
  ///
  /// `GET /` on a LiveKit server answers `200 OK` and touches nothing — it is
  /// the liveness check, so a probe costs the node a constant and reveals
  /// nothing about who asked.
  Future<_Result?> _measure(LiveKitNode node) async {
    final url = _httpUrl(node.url);
    if (url == null) return null;

    final watch = Stopwatch()..start();
    try {
      final response = await _client.get(url).timeout(_timeout);
      watch.stop();
      // Any answer is a measurement. A node behind something that returns 401
      // or 404 still answered, and how fast it did so is the whole question.
      if (response.statusCode >= 500) return null;
      return _Result(node.id, watch.elapsedMicroseconds);
    } catch (_) {
      // Unreachable, refused, timed out, or blocked by the browser's CORS
      // policy. All of them mean "cannot be measured from here", which is not
      // the same as "bad" — it just cannot win.
      return null;
    }
  }

  /// `wss://host` → `https://host/`, `ws://host` → `http://host/`.
  static Uri? _httpUrl(String livekitUrl) {
    final trimmed = livekitUrl.trim();
    final swapped = trimmed.startsWith('wss://')
        ? trimmed.replaceFirst('wss://', 'https://')
        : trimmed.startsWith('ws://')
        ? trimmed.replaceFirst('ws://', 'http://')
        : trimmed;
    final parsed = Uri.tryParse(swapped);
    if (parsed == null || !parsed.hasAuthority) return null;
    return parsed.replace(path: '/');
  }
}

class _Result {
  final String nodeId;
  final int micros;
  const _Result(this.nodeId, this.micros);
}

class _Measurement {
  final String fingerprint;
  final String? nodeId;
  final DateTime at;
  const _Measurement({
    required this.fingerprint,
    required this.nodeId,
    required this.at,
  });
}
