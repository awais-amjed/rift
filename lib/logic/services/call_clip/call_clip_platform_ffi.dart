import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../../data/classes/call_clip_audio.dart';
import '../../helper_methods.dart';
import '../host_platform.dart';
import 'call_clip_native.dart';

/// On Windows and Linux, the runner's ring; elsewhere none.
CallClipNative platformCallClip() => HostPlatform.clipsCalls
    ? (_FfiCallClip.load() ?? const CallClipNative.none())
    : const CallClipNative.none();

class _FfiCallClip implements CallClipNative {
  static const _rate = 48000;
  static int _issued = 0;

  final int Function() _available;
  final void Function(int, int) _configure;
  final void Function(int) _setWriting;
  final int Function() _frames;
  final int Function(Pointer<Int16>, int) _snapshot;
  final void Function(Pointer<Int32>, Pointer<Int32>) _format;

  _FfiCallClip._(
    this._available,
    this._configure,
    this._setWriting,
    this._frames,
    this._snapshot,
    this._format,
  );

  static _FfiCallClip? load() {
    try {
      final exe = DynamicLibrary.executable();
      return _FfiCallClip._(
        exe.lookupFunction<Int32 Function(), int Function()>(
          'rift_call_clip_available',
        ),
        exe.lookupFunction<
          Void Function(Int32, Int32),
          void Function(int, int)
        >('rift_call_clip_configure'),
        exe.lookupFunction<Void Function(Int32), void Function(int)>(
          'rift_call_clip_set_writing',
        ),
        exe.lookupFunction<Int64 Function(), int Function()>(
          'rift_call_clip_frames',
        ),
        exe.lookupFunction<
          Int64 Function(Pointer<Int16>, Int64),
          int Function(Pointer<Int16>, int)
        >('rift_call_clip_snapshot'),
        exe.lookupFunction<
          Void Function(Pointer<Int32>, Pointer<Int32>),
          void Function(Pointer<Int32>, Pointer<Int32>)
        >('rift_call_clip_format'),
      );
    } catch (e) {
      // A runner from before clips, or one that could not export them.
      HelperMethods.printDebug('[Clips] not in this runner: $e');
      return null;
    }
  }

  @override
  bool get available => _available() == 1;

  @override
  void configure(int seconds, {required bool includeMic}) =>
      _configure(seconds, includeMic ? 1 : 0);

  @override
  void setWriting(bool on) => _setWriting(on ? 1 : 0);

  @override
  CallClipAudio? snapshot() {
    final room = _frames();
    if (room <= 0) return null;
    final buffer = calloc<Int16>(room * 2);
    try {
      final frames = _snapshot(buffer, room);
      if (frames <= 0) return null;
      _logFormat();
      return CallClipAudio(
        id: ++_issued,
        pcm: Int16List.fromList(buffer.asTypedList(frames * 2)),
        rate: _rate,
        channels: 2,
        at: DateTime.now(),
      );
    } finally {
      calloc.free(buffer);
    }
  }

  /// What libwebrtc was playing the call at, for a bug report about a clip.
  void _logFormat() {
    final rate = calloc<Int32>();
    final channels = calloc<Int32>();
    try {
      _format(rate, channels);
      HelperMethods.printDebug(
        '[Clips] the call plays at ${rate.value} Hz, '
        '${channels.value} channel(s)',
      );
    } finally {
      calloc.free(rate);
      calloc.free(channels);
    }
  }
}
