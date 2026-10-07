import 'dart:js_interop';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:web/web.dart' as web;

import '../../../data/repositories/blob/blob_sink.dart';
import 'save_sink.dart';

export 'save_sink.dart';

/// On the web there is nowhere to ask about: the file goes to the browser as
/// a download once it is complete. [confirmReplace] is never needed; the
/// browser renames a clash itself.
Future<SaveSink?> chooseSaveTarget(
  String name, {
  required Future<bool> Function(String existingName) confirmReplace,
}) async => _DownloadSink(name);

/// Held in memory on the web, which has no scratch files.
Future<ScratchSink> scratchTarget(String name) async => _MemoryScratch(name);

/// Nothing to remove: the web reads a picked file where it is.
Future<void> discardCopy(XFile copy) async {}

/// Nothing to sweep, for the same reason.
Future<void> sweepCopies() async {}

/// Grows a Blob a piece at a time rather than holding a list of pieces:
/// a Blob built from a Blob references it instead of copying it, and the
/// browser moves a large one to disk.
///
/// Pieces are gathered to [_piece] first. Each new Blob still walks the parts
/// of the one before, so a file grown from what the network hands over (tens
/// of kilobytes at a time) took longer for every piece it already had:
/// measured Oct 7 in Chrome, the 8000th 64 KB piece cost almost four times
/// the 1000th. At a megabyte a piece the cost stays flat.
class _DownloadSink implements SaveSink {
  static const _piece = 1 << 20;

  final String _name;
  web.Blob _blob = web.Blob(<web.BlobPart>[].toJS);
  final _pending = BytesBuilder(copy: false);
  bool _saved = false;

  _DownloadSink(this._name);

  @override
  bool get saved => _saved;

  @override
  Future<void> add(Uint8List data) async {
    _pending.add(data);
    if (_pending.length >= _piece) _flush();
  }

  void _flush() {
    if (_pending.isEmpty) return;
    _blob = web.Blob(<web.BlobPart>[_blob, _pending.takeBytes().toJS].toJS);
  }

  @override
  Future<void> close() async {
    _flush();
    final url = web.URL.createObjectURL(_blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = _name;
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    // Revoked a moment later rather than at once: the click starts the
    // download asynchronously, and some browsers lose a URL revoked first.
    Future<void>.delayed(
      const Duration(minutes: 1),
      () => web.URL.revokeObjectURL(url),
    );
    _saved = true;
  }

  @override
  Future<void> abort() async {
    _pending.clear();
    _blob = web.Blob(<web.BlobPart>[].toJS);
  }
}

class _MemoryScratch implements ScratchSink {
  final String _name;
  final _memory = MemoryBlobSink();

  _MemoryScratch(this._name);

  @override
  XFile get file => XFile.fromData(_memory.bytes, name: _name);

  @override
  Future<void> add(Uint8List data) => _memory.add(data);

  @override
  Future<void> close() => _memory.close();

  @override
  Future<void> abort() => _memory.abort();

  @override
  Future<void> discard() async {}
}
