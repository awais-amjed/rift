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

/// Grows a Blob a piece at a time rather than holding a list of pieces:
/// a Blob built from a Blob references it instead of copying it, and the
/// browser moves a large one to disk.
class _DownloadSink implements SaveSink {
  final String _name;
  web.Blob _blob = web.Blob(<web.BlobPart>[].toJS);
  bool _saved = false;

  _DownloadSink(this._name);

  @override
  bool get saved => _saved;

  @override
  Future<void> add(Uint8List data) async {
    _blob = web.Blob(<web.BlobPart>[_blob, data.toJS].toJS);
  }

  @override
  Future<void> close() async {
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
