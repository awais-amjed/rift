import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../classes/chunked_layout.dart';
import 'blob_reader.dart';

/// A file sealed a chunk at a time, opened in order from chunk `from` on: the
/// fetching half of a [ChunkedBlobReader], one request read as it arrives
/// (`AttachmentRepository.readerFor`). Cancelling the subscription ends the
/// request.
typedef OpenedChunks = Stream<Uint8List> Function(int from);

/// Random access to a file sealed a chunk at a time, fetched as it is read.
///
/// A request costs more to start than to keep reading, and on a server whose
/// Storage still hashes the whole file before it answers one
/// (`STORAGE_FILE_ETAG_ALGORITHM` left at md5), ranged or not, it costs a lot
/// more. So reading is done in **runs** — a request from some chunk
/// on, each chunk opened as it lands — and a read that wants a chunk a run is
/// about to reach waits for it rather than starting another. A read far from
/// every run (a demuxer looking at an index at the end of the file, a seek)
/// starts one there.
///
/// A player reads in more than one place at once — the index at the end
/// while the start is still being read, sound a little apart from picture —
/// so up to [runs] run side by side. A new one past that replaces the one
/// read least lately that nothing waits on; a read is never left waiting on
/// a run that was stopped.
///
/// Each run keeps ahead of the last read it served by one chunk fewer than it
/// has been read past where it started, up to [ahead], and then pauses, which
/// holds its connection open without reading it, so a paused video does not
/// download the rest of itself. A run read once or twice — a demuxer's look
/// at an index or the middle of the file — thus brings only what was read,
/// and its request stays small (`AttachmentRepository.readerFor` asks for
/// small spans first); one being played gets its full lead within a few
/// chunks. The last [keep] chunks read or
/// landed stay in memory, enough that a demuxer moving between the sound and
/// the picture it has just read does not fetch them again; the file is never
/// held whole.
class ChunkedBlobReader implements BlobReader {
  final ChunkedLayout layout;
  final OpenedChunks _fetch;

  /// Chunks held at most.
  final int keep;

  /// Chunks a run read in order may get past the last read it served before
  /// it pauses.
  final int ahead;

  /// How far past a run's next chunk a read still waits for it.
  final int reach;

  /// Runs at once, at most, unless every one is waited on.
  final int runs;

  ChunkedBlobReader({
    required this.layout,
    required OpenedChunks fetch,
    this.keep = 24,
    this.ahead = 8,
    this.reach = 6,
    this.runs = 3,
  }) : assert(keep > ahead + reach),
       _fetch = fetch;

  /// Oldest first: what is read again moves to the end.
  final LinkedHashMap<int, Uint8List> _held = LinkedHashMap();
  final Map<int, List<Completer<Uint8List>>> _waiting = {};
  final List<_Run> _runs = [];

  /// Counts reads, so a run knows how lately it served one.
  int _reads = 0;
  bool _closed = false;

  @override
  int get length => layout.plainSize;

  /// Chunks in memory now, for tests.
  @visibleForTesting
  Iterable<int> get held => _held.keys;

  /// Where each run starts and has got to, for tests.
  @visibleForTesting
  List<({int from, int next, bool paused})> get running => [
    for (final run in _runs)
      (from: run.from, next: run.next, paused: run.paused),
  ];

  @override
  Future<Uint8List> read(int offset, int max) async {
    if (_closed) throw StateError('The file is closed');
    if (offset < 0) throw RangeError.value(offset, 'offset');
    if (offset >= length || max <= 0) return Uint8List(0);
    final index = offset ~/ layout.chunkSize;
    final chunk = await _chunk(index);
    final from = offset - layout.plainOffset(index);
    return Uint8List.sublistView(
      chunk,
      from,
      math.min(chunk.length, from + max),
    );
  }

  Future<Uint8List> _chunk(int index) {
    _reads++;
    final held = _held.remove(index);
    if (held != null) {
      _held[index] = held;
      // The run that brought it keeps its place ahead of this read.
      for (final run in _runs) {
        if (run.from <= index && index < run.next) run.served(index, _reads);
      }
      _pace();
      return Future.value(held);
    }
    final waiter = Completer<Uint8List>();
    _waiting.putIfAbsent(index, () => []).add(waiter);
    (_runFor(index) ?? _start(index)).served(index, _reads);
    _pace();
    return waiter.future;
  }

  /// The run about to reach chunk [index], if any.
  _Run? _runFor(int index) {
    for (final run in _runs) {
      if (run.reaches(index, reach)) return run;
    }
    return null;
  }

  bool _waitedOn(_Run run) =>
      _waiting.keys.any((index) => run.reaches(index, reach));

  _Run _start(int index) {
    if (_runs.length >= runs) {
      final idle = _runs.where((run) => !_waitedOn(run)).toList()
        ..sort((a, b) => a.lastRead.compareTo(b.lastRead));
      if (idle.isNotEmpty) _stop(idle.first);
    }
    final run = _Run(index);
    _runs.add(run);
    run.subscription = _fetch(index).listen(
      (plain) {
        if (!_runs.contains(run)) return;
        _land(run.next++, plain);
        _pace();
      },
      onError: (Object error) {
        if (!_runs.remove(run)) return;
        _orphans(run, error);
      },
      onDone: () {
        if (!_runs.remove(run)) return;
        // Whatever it was still to bring, it was the only way in.
        _orphans(run, const FormatException('The file ends early'));
      },
      cancelOnError: true,
    );
    return run;
  }

  void _stop(_Run run) {
    _runs.remove(run);
    unawaited(run.stop());
  }

  /// Fails the reads that waited on [run], which has ended, unless another
  /// run will still bring what they want.
  void _orphans(_Run run, Object error) {
    final lost = _waiting.keys
        .where((index) => run.reaches(index, reach) && _runFor(index) == null)
        .toList();
    for (final index in lost) {
      for (final waiter in _waiting.remove(index)!) {
        waiter.completeError(error);
      }
    }
    _pace();
  }

  void _land(int index, Uint8List plain) {
    _held.remove(index);
    _held[index] = plain;
    while (_held.length > keep) {
      _held.remove(_held.keys.first);
    }
    for (final waiter in _waiting.remove(index) ?? const []) {
      waiter.complete(plain);
    }
  }

  /// Pauses each run once it is its lead past the last read it served, and
  /// lets it go again when a read catches up or waits for what it brings.
  void _pace() {
    for (final run in _runs) {
      run.pace(
        hold: !_waitedOn(run) && run.next > run.wanted + run.lead(ahead),
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final stopping = [for (final run in _runs) run.stop()];
    _runs.clear();
    _held.clear();
    final waiting = [for (final list in _waiting.values) ...list];
    _waiting.clear();
    for (final waiter in waiting) {
      waiter.completeError(StateError('The file is closed'));
    }
    await Future.wait(stopping);
  }
}

/// One request, from chunk [from] on.
class _Run {
  final int from;

  /// The chunk the next to land is.
  int next;

  /// The chunk the last read it served wanted, which it keeps ahead of.
  int wanted;

  /// When it last served a read, in reads.
  int lastRead = 0;
  late final StreamSubscription<Uint8List> subscription;
  bool paused = false;

  _Run(this.from) : next = from, wanted = from;

  /// Whether chunk [index] is one this run is about to bring.
  bool reaches(int index, int reach) => index >= next && index <= next + reach;

  /// Chunks it may get past the last read it served: one fewer than it has
  /// been read past where it started, at most [ahead].
  int lead(int ahead) => (wanted - from - 1).clamp(0, ahead);

  void served(int index, int read) {
    wanted = index;
    lastRead = read;
  }

  void pace({required bool hold}) {
    if (hold == paused) return;
    paused = hold;
    hold ? subscription.pause() : subscription.resume();
  }

  Future<void> stop() => subscription.cancel();
}
