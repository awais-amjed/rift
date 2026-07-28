import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records a voice note to a temporary file and hands back its bytes, so the
/// composer widget never touches the platform recorder or the filesystem.
///
/// The recording is deleted from disk as soon as it has been read — a voice
/// note only ever exists in memory until it is encrypted and uploaded.
class VoiceNoteRecorder {
  /// AAC-LC in an m4a container, mono @64kbps: small enough to send as an
  /// attachment and playable by `audioplayers` on every target.
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.aacLc,
    numChannels: 1,
    bitRate: 64000,
  );

  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Throws if the platform can't start capturing (no microphone, denied).
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rift_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(_config, path: path);
    _path = path;
  }

  /// Stops and returns the recorded bytes, or null if nothing was captured.
  Future<Uint8List?> stop() async {
    _path = null;
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    return bytes;
  }

  /// Stops and throws the recording away.
  Future<void> cancel() async {
    final path = _path;
    _path = null;
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing worth keeping either way.
    }
    if (path != null) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
  }

  void dispose() => _recorder.dispose();
}
