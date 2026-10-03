import 'dart:async';

import 'package:http/http.dart' as http;

/// Whether any of the servers you joined answers at all, for `NetworkCubit`
/// to settle a platform's "not sure" (`NetworkReading.unsure`).
///
/// Only those servers: Rift asks nobody else whether there is internet. Any
/// HTTP answer counts, whatever its status — an old server with no status
/// page says 404, and that is still a server reached over the network.
class ServerReachProbe {
  /// Long enough for a slow round trip, short enough that the chip is not
  /// held up behind a server that is down.
  static const _timeout = Duration(seconds: 4);

  final http.Client _client;

  ServerReachProbe({http.Client? client}) : _client = client ?? http.Client();

  /// True once one of [urls] answers; false when none does. Null when there
  /// is nobody to ask, so the caller falls back on the platform's word.
  Future<bool?> anyAnswers(Iterable<String> urls) async {
    final targets = urls.toSet();
    if (targets.isEmpty) return null;
    final answered = Completer<bool>();
    var pending = targets.length;
    for (final url in targets) {
      unawaited(
        _answers(url).then((ok) {
          pending--;
          if (answered.isCompleted) return;
          if (ok) {
            answered.complete(true);
          } else if (pending == 0) {
            answered.complete(false);
          }
        }),
      );
    }
    return answered.future;
  }

  Future<bool> _answers(String url) async {
    try {
      await _client.head(Uri.parse(url)).timeout(_timeout);
      return true;
    } catch (_) {
      return false;
    }
  }
}
