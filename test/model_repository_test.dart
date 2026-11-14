import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/classes/model_file.dart';
import 'package:rift/data/classes/model_progress.dart';
import 'package:rift/data/repositories/model_repository.dart';
import 'package:rift/data/repositories/model_transfer.dart';

/// Downloading a model: resumed where a broken try stopped, refused when the
/// bytes are not the pinned file, and old versions swept only once nothing
/// has used them for a while.
void main() {
  late Directory dir;
  late List<int> body;
  late ModelFile file;
  late List<http.BaseRequest> requests;
  var now = DateTime(2026, 11, 15);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('rift_models_test');
    body = List.generate(50000, (i) => Random(i).nextInt(256));
    final source = File('${dir.path}/source')..writeAsBytesSync(body);
    file = ModelFile(
      id: 'test',
      name: 'test model',
      published: 'test.v1.bin',
      size: body.length,
      sha256: await sha256Of(source),
    );
    source.deleteSync();
    requests = [];
    now = DateTime(2026, 11, 15);
  });

  tearDown(() => dir.delete(recursive: true));

  ModelRepository repo(
    Future<http.StreamedResponse> Function(http.BaseRequest) answer,
  ) => ModelRepository(
    client: MockClient.streaming((request, _) {
      requests.add(request);
      return answer(request);
    }),
    folder: () async => dir,
    clock: () => now,
    retryDelays: const [Duration.zero, Duration.zero],
  );

  /// The file as a server that honours ranges sends it.
  Future<http.StreamedResponse> serve(http.BaseRequest request) async {
    final range = request.headers['range'];
    final from = range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    return http.StreamedResponse(
      Stream.value(body.sublist(from)),
      from == 0 ? 200 : 206,
      headers: {
        if (from > 0)
          'content-range': 'bytes $from-${body.length - 1}/${body.length}',
      },
    );
  }

  File target() => File('${dir.path}/${file.localName}');
  File part() => File('${target().path}.part');

  test('downloads, checks and keeps the file', () async {
    final models = repo(serve);
    final seen = <ModelProgress>[];
    final sub = models.progress.listen(seen.add);
    final got = await models.fetch(file);
    await sub.cancel();

    expect(got.readAsBytesSync(), body);
    expect(part().existsSync(), isFalse);
    expect(seen.last.status, ModelStatus.success);
    // A second ask goes nowhere.
    await models.fetch(file);
    expect(requests, hasLength(1));
  });

  test('carries on from what a broken try kept', () async {
    part().writeAsBytesSync(body.sublist(0, 20000));
    final got = await repo(serve).fetch(file);
    expect(requests.single.headers['range'], 'bytes=20000-');
    expect(got.readAsBytesSync(), body);
  });

  test('starts over when the server sends the whole file', () async {
    part().writeAsBytesSync(body.sublist(0, 20000));
    final got = await repo(
      (_) async => http.StreamedResponse(Stream.value(body), 200),
    ).fetch(file);
    expect(got.readAsBytesSync(), body);
  });

  test('a dropped connection is picked up where it stopped', () async {
    var first = true;
    final got = await repo((request) async {
      if (!first) return serve(request);
      first = false;
      final broken = StreamController<List<int>>();
      broken.add(body.sublist(0, 30000));
      broken.addError(http.ClientException('connection reset'));
      unawaited(broken.close());
      return http.StreamedResponse(broken.stream, 200);
    }).fetch(file);
    expect(requests.last.headers['range'], 'bytes=30000-');
    expect(got.readAsBytesSync(), body);
  });

  test('refuses bytes that are not the pinned file', () async {
    final wrong = List<int>.of(body)..[100] ^= 1;
    final models = repo(
      (_) async => http.StreamedResponse(Stream.value(wrong), 200),
    );
    await expectLater(models.fetch(file), throwsA(isA<ModelUnavailable>()));
    expect(target().existsSync(), isFalse);
    expect(part().existsSync(), isFalse);
    // Tried again from scratch, not from the bad copy.
    expect(requests.map((r) => r.headers['range']), everyElement(isNull));

    // Asked again at once, it does not go back out…
    final tries = requests.length;
    await expectLater(models.fetch(file), throwsA(isA<ModelUnavailable>()));
    expect(requests, hasLength(tries));
    // …unless somebody pressed Retry.
    await expectLater(
      models.fetch(file, retry: true),
      throwsA(isA<ModelUnavailable>()),
    );
    expect(requests.length, greaterThan(tries));
  });

  test('a file not in the release is asked for once', () async {
    final models = repo(
      (_) async => http.StreamedResponse(const Stream.empty(), 404),
    );
    await expectLater(models.fetch(file), throwsA(isA<ModelUnavailable>()));
    expect(requests, hasLength(1));
  });

  test('sweeps old versions once nothing has used them', () async {
    final models = repo(serve);
    await models.fetch(file);
    final old = File('${dir.path}/test.v0-000000000000.bin')
      ..writeAsBytesSync([1]);
    final oldPart = File('${dir.path}/other-111111111111.bin.part')
      ..writeAsBytesSync([1]);
    final recent = File('${dir.path}/newer-222222222222.bin')
      ..writeAsBytesSync([1]);
    final longAgo = now.subtract(const Duration(days: 20));
    old.setLastModifiedSync(longAgo);
    oldPart.setLastModifiedSync(longAgo);
    target().setLastModifiedSync(longAgo);
    recent.setLastModifiedSync(now.subtract(const Duration(days: 2)));

    await models.sweep([file]);
    expect(old.existsSync(), isFalse);
    expect(oldPart.existsSync(), isFalse);
    // Another version of Rift may still be using it.
    expect(recent.existsSync(), isTrue);
    // This version's, however long since it was used.
    expect(target().existsSync(), isTrue);
  });

  test('using a model marks it used', () async {
    final models = repo(serve);
    await models.fetch(file);
    target().setLastModifiedSync(DateTime(2026, 1, 1));
    await models.present(file);
    expect(target().lastModifiedSync(), now);
  });

  test('the name on disk carries the hash', () {
    expect(file.localName, startsWith('test.v1-'));
    expect(file.localName, endsWith('.bin'));
    expect(file.localName, contains(file.sha256.substring(0, 12)));
  });
}
