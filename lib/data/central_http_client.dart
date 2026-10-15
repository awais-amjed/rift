import 'dart:async';

import 'package:http/http.dart' as http;

/// The HTTP client central's Supabase client runs on: a request that carries
/// little gives up after [answerWithin] without an answer.
///
/// Without it a call to a central that cannot be reached at all — the server
/// down rather than refusing — waited out the system's connect timeout, about
/// two minutes on Linux, with the sign-in button spinning, before
/// [CentralFailure] could say anything. A self-hosted server's calls already
/// stop at the same 15 seconds (`ServerRepository`).
///
/// Only the wait for the answer's headers is timed, and only for a small
/// request: an upload's body goes out before its answer comes back, so a
/// limit there would cut off a backup or an attachment on a slow line. A
/// download's body arrives after the headers and is not timed either.
class CentralHttpClient extends http.BaseClient {
  static const defaultAnswerWithin = Duration(seconds: 15);

  /// Bodies up to this size are timed: every query, RPC and sign-in, and
  /// none of the uploads that could take longer than the limit to send.
  static const smallBody = 64 * 1024;

  final http.Client _inner;
  final Duration answerWithin;

  CentralHttpClient({
    http.Client? inner,
    this.answerWithin = defaultAnswerWithin,
  }) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final sent = _inner.send(request);
    final length = request.contentLength;
    // A streamed request has no length until it is sent, and is an upload.
    if (length == null || length > smallBody) return sent;
    return sent.timeout(answerWithin);
  }

  @override
  void close() => _inner.close();
}
