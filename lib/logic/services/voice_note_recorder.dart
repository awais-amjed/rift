import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// A finished recording, named for the format it was actually made in.
typedef VoiceNote = ({Uint8List bytes, String name, String mime});

/// Records a voice note to a temporary file and hands back its bytes, so the
/// composer widget never touches the platform recorder or the filesystem.
///
/// The recording is deleted from disk as soon as it has been read — a voice
/// note only ever exists in memory until it is encrypted and uploaded.
///
/// A browser has no disk to record to. There the recording is a blob the
/// page holds, read back through its URL, and its format is whatever the
/// browser can make: Safari records AAC like everything else, while Chrome
/// and Firefox only make Opus in WebM. Asking them for AAC anyway is what
/// made every voice note on the web fail to start.
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
  bool _webm = false;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Throws if the platform can't start capturing (no microphone, denied).
  Future<void> start() async {
    if (kIsWeb) {
      _webm = !await _recorder.isEncoderSupported(AudioEncoder.aacLc);
      await _recorder.start(
        _webm ? _config.copyWith(encoder: AudioEncoder.opus) : _config,
        path: '',
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rift_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(_config, path: path);
    _path = path;
  }

  /// Stops and returns the recording, or null if nothing was captured.
  Future<VoiceNote?> stop() async {
    _path = null;
    final path = await _recorder.stop();
    if (path == null) return null;
    if (kIsWeb) {
      // `path` is the blob's URL, and fetching it is how a page reads a blob.
      final bytes = (await http.get(Uri.parse(path))).bodyBytes;
      return _webm
          ? (bytes: bytes, name: 'Voice message.webm', mime: 'audio/webm')
          : (bytes: bytes, name: 'Voice message.m4a', mime: 'audio/mp4');
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    await file.delete().catchError((_) => file);
    return (bytes: bytes, name: 'Voice message.m4a', mime: 'audio/mp4');
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
