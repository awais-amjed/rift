import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../data/repositories/blob/blob_reader.dart';
import '../../../src/rust/api/clips.dart';
import '../../helper_methods.dart';
import 'chat_clip.dart';

/// A chat video played by ExoPlayer, with the phone's own decoders, into a
/// Flutter texture (`ChatClips.kt` in the Android app). The player asks for
/// the file a block at a time over the channel, and is answered from the
/// clip's [BlobReader], as Rust's player is on the desktop.
class AndroidChatClip implements ChatClip {
  static const MethodChannel _channel = MethodChannel('rift/chat_clip');

  /// What Flutter's `Texture` draws, which names the clip both sides.
  final int textureId;

  final StreamController<ClipEvent> _events;
  final BlobReader _file;

  /// Quarter turns the card gives the picture, where the texture does not
  /// turn it itself.
  int _turns = 0;

  /// The last time the player gave, and when: [time] is asked four times a
  /// second and answers at once, so it runs on from this while playing.
  ({Duration position, Duration? length, bool playing}) _last = (
    position: Duration.zero,
    length: null,
    playing: false,
  );
  final Stopwatch _since = Stopwatch();
  bool _asking = false;

  AndroidChatClip._(this.textureId, this._events, this._file);

  static final Map<int, AndroidChatClip> _open = {};
  static bool _listening = false;

  static void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler(_heard);
  }

  static Future<Object?> _heard(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final clip = _open[args['id'] as int];
    switch (call.method) {
      case 'read':
        if (clip == null) throw PlatformException(code: 'closed');
        return clip._read(args['offset'] as int, args['length'] as int);
      case 'event':
        clip?._event(args);
    }
    return null;
  }

  /// What the player asked for, from the clip's file.
  Future<Uint8List> _read(int offset, int length) async {
    try {
      return await _file.readFully(offset, length);
    } catch (e) {
      // Not the error itself, which may carry the file's address.
      final why = e is FormatException ? e.message : '${e.runtimeType}';
      HelperMethods.printDebug('[ChatClip] read failed: $why');
      throw PlatformException(code: 'read', message: why);
    }
  }

  void _event(Map<String, Object?> args) {
    final kind = switch (args['kind']) {
      'pictureSize' => ClipEventKind.pictureSize,
      'ended' => ClipEventKind.ended,
      'cannotDecode' => ClipEventKind.cannotDecode,
      _ => ClipEventKind.failed,
    };
    if (kind == ClipEventKind.pictureSize) {
      _turns = ((args['turn'] as int? ?? 0) ~/ 90) % 4;
    }
    if (kind == ClipEventKind.ended) {
      _last = (
        position: _last.length ?? _last.position,
        length: _last.length,
        playing: false,
      );
      _since.stop();
    }
    if (_events.isClosed) return;
    _events.add(
      ClipEvent(
        texture: BigInt.from(textureId),
        kind: kind,
        width: args['width'] as int? ?? 0,
        height: args['height'] as int? ?? 0,
        reason: args['reason'] as String? ?? '',
      ),
    );
  }

  @override
  Stream<ClipEvent> get events => _events.stream;

  /// [ChatClip.open], on Android.
  static Future<({ChatClip? clip, String? error})> open(BlobReader file) async {
    _listen();
    try {
      final id = await _channel.invokeMethod<int>('open', {
        'length': file.length,
      });
      if (id == null) throw StateError('No player');
      // Not a broadcast: what the player says before the card listens
      // waits for it.
      final clip = AndroidChatClip._(id, StreamController<ClipEvent>(), file);
      _open[id] = clip;
      return (clip: clip, error: null);
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] open: $e');
      await file.close();
      return (clip: null, error: '$e');
    }
  }

  /// [ChatClip.posterToSend] on Android: from the picked file where it lies
  /// ([path]) or from [bytes].
  static Future<Uint8List?> poster({
    String? path,
    Uint8List? bytes,
    int longest = 880,
  }) async {
    try {
      return await _channel.invokeMethod<Uint8List>('poster', {
        'path': ?path,
        'bytes': ?bytes,
        'longest': longest,
      });
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] poster: $e');
      return null;
    }
  }

  @override
  Widget picture() => _turns == 0
      ? Texture(textureId: textureId)
      : RotatedBox(
          quarterTurns: _turns,
          child: Texture(textureId: textureId),
        );

  @override
  Future<bool> play() async {
    final played = await _quietly('play');
    if (played) _ask();
    return played;
  }

  @override
  Future<void> pause() async {
    await _quietly('pause');
    _ask();
  }

  @override
  Future<void> seek(Duration to) async {
    _last = (position: to, length: _last.length, playing: _last.playing);
    _since
      ..reset()
      ..start();
    await _quietly('seek', {'ms': to.inMilliseconds.clamp(0, 1 << 40)});
    _ask();
  }

  @override
  Future<void> setVolume(double volume) =>
      _quietly('volume', {'volume': volume});

  @override
  ({Duration? position, Duration? length}) time() {
    _ask();
    var position = _last.position;
    if (_last.playing) position += _since.elapsed;
    final length = _last.length;
    if (length != null && position > length) position = length;
    return (position: position, length: length);
  }

  /// Asks the player where it is, once at a time.
  void _ask() {
    if (_asking || _events.isClosed) return;
    _asking = true;
    unawaited(
      _channel
          .invokeMapMethod<String, Object?>('time', {'id': textureId})
          .then((t) {
            if (t == null) return;
            final length = t['length'] as int?;
            _last = (
              position: Duration(milliseconds: t['position'] as int? ?? 0),
              length: length == null ? null : Duration(milliseconds: length),
              playing: t['playing'] == true,
            );
            _since
              ..reset()
              ..start();
          })
          .catchError((_) {})
          .whenComplete(() => _asking = false),
    );
  }

  /// Stops it and lets the file go: a read still waiting fails.
  @override
  Future<void> close() async {
    await _quietly('close');
    _open.remove(textureId);
    await _file.close();
    await _events.close();
  }

  /// Whether [method] went through; a failure is logged, not thrown.
  Future<bool> _quietly(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<Object?>(method, {'id': textureId, ...?args});
      return true;
    } catch (e) {
      HelperMethods.printDebug('[ChatClip] $method: $e');
      return false;
    }
  }
}
