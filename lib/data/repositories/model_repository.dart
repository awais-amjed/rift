import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../logic/helper_methods.dart';
import '../../logic/services/storage_namespace.dart';
import '../classes/model_file.dart';
import '../classes/model_progress.dart';
import 'model_transfer.dart';

/// A model could not be had: not downloaded and could not be, for now.
class ModelUnavailable implements Exception {
  final ModelFile file;
  final String reason;

  const ModelUnavailable(this.file, this.reason);

  @override
  String toString() => '${file.id} unavailable: $reason';
}

/// The models Rift downloads instead of shipping (`ModelCatalog`), kept in
/// one folder beside the profiles: every profile on the device shares them,
/// and an update leaves them in place, so each version of a model is fetched
/// once per device.
///
/// A file in the folder under its [ModelFile.localName] has passed its hash:
/// it is only ever renamed there after the check. Until then it is a `.part`,
/// which the next try carries on from. Two Rift processes asking at once (two
/// profiles at a first start) take turns on a lock file beside it, and the
/// second finds the file the first brought.
///
/// Not for the web, which has no folder to keep them in; there a model is
/// served beside the app ([servedBeside]).
class ModelRepository {
  ModelRepository({
    http.Client? client,
    Future<Directory> Function()? folder,
    DateTime Function()? clock,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 10)],
    this.stallAfter = const Duration(seconds: 30),
    String? source,
  }) : _source = source ?? _sourceOverride(),
       _client = client ?? http.Client(),
       _folder = folder ?? _defaultFolder,
       _clock = clock ?? DateTime.now;

  static final ModelRepository instance = ModelRepository();

  /// A file this version does not use is left this long after anything last
  /// used it, since another version of Rift on this device may still: a
  /// development build beside an installed one would otherwise each delete
  /// the other's model and fetch its own again at every start.
  static const Duration keepUnused = Duration(days: 14);

  /// After a model fails, asking again within this long fails at once rather
  /// than going back out. A picture asks for the classifier each time one is
  /// drawn, and a failing network would be asked dozens of times a second.
  /// [fetch] with `retry: true` (a person pressing Retry) skips it.
  static const Duration restAfterFailure = Duration(minutes: 1);

  /// How long to wait before each further try in one fetch.
  final List<Duration> retryDelays;

  /// A download that has sent nothing for this long is dropped and tried
  /// again from where it got to.
  final Duration stallAfter;

  /// Where to fetch from instead of the release, ending in `/`: null for
  /// the release.
  final String? _source;
  final http.Client _client;
  final Future<Directory> Function() _folder;
  final DateTime Function() _clock;

  final _progress = StreamController<ModelProgress>.broadcast();
  final Map<String, Future<File>> _fetching = {};
  final Map<String, (DateTime, ModelUnavailable)> _failed = {};
  Future<Directory>? _directory;

  /// One download at a time, in the order asked: the classifier first at a
  /// first start, then whatever the calls need.
  Future<void> _queue = Future.value();

  /// Every download's progress as it runs and how it ended, for the bar that
  /// shows it (`ModelsCubit`).
  Stream<ModelProgress> get progress => _progress.stream;

  /// `RIFT_MODEL_SOURCE`: a URL to fetch the files from instead of the
  /// release, for trying a model out before publishing it. A file from
  /// there must match its hash all the same.
  static String? _sourceOverride() {
    if (kIsWeb) return null;
    final source = Platform.environment['RIFT_MODEL_SOURCE'];
    if (source == null || source.isEmpty) return null;
    return source.endsWith('/') ? source : '$source/';
  }

  Uri _urlOf(ModelFile file) {
    final source = _source;
    return source == null ? file.url : Uri.parse('$source${file.published}');
  }

  static Future<Directory> _defaultFolder() async =>
      Directory('${await StorageNamespace.sharedDirectory()}/models');

  Future<Directory> _dir() => _directory ??= () async {
    final dir = await _folder();
    await dir.create(recursive: true);
    return dir;
  }();

  /// [file] if it is already on this device, without fetching it. Marks it
  /// used, which keeps another version's [sweep] off it.
  Future<File?> present(ModelFile file) async {
    final target = File('${(await _dir()).path}/${file.localName}');
    if (!await target.exists()) return null;
    try {
      await target.setLastModified(_clock());
    } on FileSystemException {
      // Only the sweep reads it, and a model kept a little long is harmless.
    }
    return target;
  }

  /// [file], downloaded first if it is not here. Throws [ModelUnavailable]
  /// when it could not be fetched, at once when that happened within
  /// [restAfterFailure] unless [retry].
  Future<File> fetch(ModelFile file, {bool retry = false}) async {
    final here = await present(file);
    if (here != null) return here;
    final failed = _failed[file.localName];
    if (!retry &&
        failed != null &&
        _clock().difference(failed.$1) < restAfterFailure) {
      throw failed.$2;
    }
    // A block, not an arrow: `remove` hands back this very future, and
    // `whenComplete` waits for a future its callback returns.
    return _fetching[file.localName] ??= _enqueue(file).whenComplete(() {
      _fetching.remove(file.localName);
    });
  }

  Future<File> _enqueue(ModelFile file) {
    final run = _queue.then((_) => _download(file));
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<File> _download(ModelFile file) async {
    final dir = await _dir();
    final target = File('${dir.path}/${file.localName}');
    final part = File('${target.path}.part');
    final lock = await File('${target.path}.lock').open(mode: FileMode.append);
    var received = 0;
    void report(int bytes, ModelStatus status) {
      received = bytes;
      _progress.add(ModelProgress(file, bytes, status));
    }

    try {
      await lock.lock(FileLock.blockingExclusive);
      // Brought by another Rift while this one waited for the lock.
      if (await target.exists()) return target;
      for (var attempt = 0; ; attempt++) {
        try {
          await transferModel(
            client: _client,
            file: file,
            url: _urlOf(file),
            part: part,
            stallAfter: stallAfter,
            onProgress: (bytes) => report(bytes, ModelStatus.loading),
          );
          break;
        } on ModelTransferFailed catch (e) {
          if (!e.worthRetrying || attempt >= retryDelays.length) rethrow;
          HelperMethods.printDebug(
            'ModelRepository: ${file.id} – $e, trying again',
          );
          await Future<void>.delayed(retryDelays[attempt]);
        } on IOException catch (e) {
          if (attempt >= retryDelays.length) rethrow;
          HelperMethods.printDebug(
            'ModelRepository: ${file.id} – $e, trying again',
          );
          await Future<void>.delayed(retryDelays[attempt]);
        }
      }
      await part.rename(target.path);
      _failed.remove(file.localName);
      report(file.size, ModelStatus.success);
      HelperMethods.printDebug('ModelRepository: ${file.id} downloaded');
      return target;
    } catch (e) {
      final failure = ModelUnavailable(file, '$e');
      _failed[file.localName] = (_clock(), failure);
      report(received, ModelStatus.failure);
      HelperMethods.printDebug('ModelRepository: $failure');
      throw failure;
    } finally {
      await lock.close();
    }
  }

  /// Deletes what in the folder is not one of [keep] and has not been used
  /// for [keepUnused]: older versions of a model, and whatever a broken try
  /// at one left behind.
  Future<void> sweep(Iterable<ModelFile> keep) async {
    final current = {for (final file in keep) file.localName};
    final before = _clock().subtract(keepUnused);
    await for (final entity in (await _dir()).list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      final model = name.replaceFirst(RegExp(r'\.(part|lock)$'), '');
      if (current.contains(model)) continue;
      try {
        if ((await entity.lastModified()).isAfter(before)) continue;
        await entity.delete();
        HelperMethods.printDebug('ModelRepository: swept $name');
      } on FileSystemException {
        // Gone already, or held open by another Rift: the next sweep.
      }
    }
  }

  /// [file]'s bytes on the web, from beside the app, where the web build
  /// puts a copy (`scripts/build_web.sh`): the same origin as the code that
  /// reads it, so nothing to check it against.
  Future<Uint8List> servedBeside(ModelFile file) async {
    final response = await _client.get(
      Uri.base.resolve('models/${file.published}'),
    );
    if (response.statusCode != 200) {
      throw ModelUnavailable(file, 'HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
