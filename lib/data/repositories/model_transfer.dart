import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/dart.dart';
import 'package:http/http.dart' as http;

import '../classes/model_file.dart';

/// Why a try at a model failed, and whether trying again could help.
class ModelTransferFailed implements Exception {
  final String reason;

  /// False when asking again will get the same answer: the file is not in
  /// the release, or GitHub refuses it.
  final bool worthRetrying;

  const ModelTransferFailed(this.reason, {this.worthRetrying = true});

  @override
  String toString() => reason;
}

/// One try at bringing [file] into [part] from [url]: the rest of it when [part] holds
/// the start of it already, or all of it when the server will not send a
/// part. Ends with [part] holding the whole file, checked against its hash,
/// or throws [ModelTransferFailed].
///
/// A try that breaks off keeps what arrived, so the next one carries on from
/// there; a phone that drops off Wi-Fi halfway does not start over. A file
/// that turns out longer than it should be, or not the file at all, is
/// thrown away, since nothing kept from it can be trusted.
Future<void> transferModel({
  required http.Client client,
  required ModelFile file,
  required Uri url,
  required File part,
  required Duration stallAfter,
  required void Function(int received) onProgress,
}) async {
  var have = await part.exists() ? await part.length() : 0;
  if (have > file.size) {
    await part.delete();
    have = 0;
  }
  if (have < file.size) {
    have = await _receive(
      client,
      file,
      url,
      part,
      have,
      stallAfter,
      onProgress,
    );
  }
  if (have != file.size) {
    throw ModelTransferFailed('ended at $have of ${file.size} bytes');
  }
  final hash = await sha256Of(part);
  if (hash != file.sha256) {
    await part.delete();
    throw const ModelTransferFailed('did not match its hash');
  }
}

/// Asks for the bytes from [have] on and appends them to [part]. Returns how
/// many bytes [part] holds after.
Future<int> _receive(
  http.Client client,
  ModelFile file,
  Uri url,
  File part,
  int have,
  Duration stallAfter,
  void Function(int received) onProgress,
) async {
  final request = http.Request('GET', url);
  if (have > 0) request.headers['range'] = 'bytes=$have-';
  final response = await client.send(request).timeout(stallAfter);

  switch (response.statusCode) {
    case 206 when _startOf(response) == have:
      break;
    case 200:
      // The whole file, whatever was asked for: start the copy over.
      have = 0;
    case 206 || 416:
      // A part from the wrong place, or no part at all of what was kept:
      // what was kept is not the start of this file.
      await response.stream.drain<void>();
      await part.delete();
      throw const ModelTransferFailed('the kept start did not fit');
    case final code:
      await response.stream.drain<void>();
      throw ModelTransferFailed(
        'HTTP $code',
        worthRetrying: code >= 500 || code == 408 || code == 429,
      );
  }

  final sink = part.openWrite(
    mode: have == 0 ? FileMode.write : FileMode.append,
  );
  // Several times a second at most: each one is a rebuild somewhere.
  final step = file.size ~/ 200 + 1;
  var reported = have;
  onProgress(have);
  try {
    await for (final chunk in response.stream.timeout(stallAfter)) {
      have += chunk.length;
      if (have > file.size) {
        throw const ModelTransferFailed('longer than it should be');
      }
      sink.add(chunk);
      if (have - reported >= step) {
        reported = have;
        onProgress(have);
      }
    }
  } on TimeoutException {
    throw const ModelTransferFailed('stalled');
  } on http.ClientException catch (e) {
    throw ModelTransferFailed('broke off: ${e.message}');
  } finally {
    await sink.close();
    if (have > file.size) await part.delete();
  }
  onProgress(have);
  return have;
}

/// Where a 206's part starts, from its `Content-Range` (`bytes 100-199/200`).
int? _startOf(http.StreamedResponse response) {
  final range = response.headers['content-range'];
  final match = range == null
      ? null
      : RegExp(r'bytes (\d+)-').firstMatch(range);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// [file]'s SHA-256 as lower-case hex, worked out on another isolate: a
/// model is tens of megabytes, which would stall the screen for a moment.
Future<String> sha256Of(File file) {
  final path = file.path;
  return Isolate.run(() async {
    final sink = const DartSha256().newHashSink();
    await for (final chunk in File(path).openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final bytes = (await sink.hash()).bytes;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  });
}
