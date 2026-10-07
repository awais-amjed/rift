import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';

import 'save_sink.dart';

export 'save_sink.dart';

/// Ask where to save [name], and answer what to write it to — null when the
/// person cancelled. [confirmReplace] is asked when a desktop dialog picked a
/// file that already exists; GTK's does not ask on its own.
Future<SaveSink?> chooseSaveTarget(
  String name, {
  required Future<bool> Function(String existingName) confirmReplace,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return _DialogAfterSink._(await _scratchFile(name), name);
  }
  final location = await getSaveLocation(suggestedName: name);
  if (location == null) return null;
  final target = File(location.path);
  if (await target.exists() &&
      !await confirmReplace(target.uri.pathSegments.last)) {
    return null;
  }
  return _FileSink._(target);
}

/// A scratch file for a download about to be sent on.
Future<ScratchSink> scratchTarget(String name) async =>
    _ScratchSink._(await _scratchFile(name));

final _rng = Random.secure();

/// A fresh file in its own folder under the app's cache directory, so two
/// downloads of the same name never meet. The cache and not the temporary
/// directory: on many Linux systems `/tmp` is held in memory, which is the
/// one place a big file must not go.
Future<File> _scratchFile(String name) async {
  final base = await getApplicationCacheDirectory();
  final folder = Directory(
    '${base.path}/rift-files/${_rng.nextInt(1 << 32).toRadixString(16)}',
  );
  await folder.create(recursive: true);
  final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
  return File('${folder.path}/${safe.isEmpty ? 'file' : safe}');
}

/// Writes to `<file>.part` and renames it over [_target] once complete.
class _FileSink implements SaveSink {
  final File _target;
  final File _part;
  RandomAccessFile? _out;
  bool _saved = false;

  _FileSink._(this._target) : _part = File('${_target.path}.part');

  @override
  bool get saved => _saved;

  @override
  Future<void> add(Uint8List data) async {
    _out ??= await _part.open(mode: FileMode.write);
    await _out!.writeFrom(data);
  }

  @override
  Future<void> close() async {
    _out ??= await _part.open(mode: FileMode.write);
    await _out!.close();
    if (await _target.exists()) await _target.delete();
    await _part.rename(_target.path);
    _saved = true;
  }

  @override
  Future<void> abort() async {
    await _out?.close();
    if (await _part.exists()) await _part.delete();
  }
}

/// Downloads to a scratch file, then hands it to the system's save dialog.
class _DialogAfterSink implements SaveSink {
  final _FileSink _scratch;
  final String _name;
  bool _saved = false;

  _DialogAfterSink._(File scratch, this._name)
    : _scratch = _FileSink._(scratch);

  @override
  bool get saved => _saved;

  @override
  Future<void> add(Uint8List data) => _scratch.add(data);

  @override
  Future<void> close() async {
    await _scratch.close();
    try {
      final path = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: _scratch._target.path,
          fileName: _name,
        ),
      );
      _saved = path != null;
    } finally {
      await _remove(_scratch._target);
    }
  }

  @override
  Future<void> abort() => _scratch.abort();
}

class _ScratchSink implements ScratchSink {
  final _FileSink _sink;

  _ScratchSink._(File file) : _sink = _FileSink._(file);

  @override
  XFile get file => XFile(_sink._target.path);

  @override
  Future<void> add(Uint8List data) => _sink.add(data);

  @override
  Future<void> close() => _sink.close();

  @override
  Future<void> abort() => _sink.abort();

  @override
  Future<void> discard() => _remove(_sink._target);
}

Future<void> _remove(File file) async {
  try {
    await file.parent.delete(recursive: true);
  } catch (_) {}
}
