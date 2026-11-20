import '../../../data/classes/call_clip_audio.dart';
import 'call_clip_platform_stub.dart'
    if (dart.library.ffi) 'call_clip_platform_ffi.dart';

/// The runner's ring of the call (`native/call_clip`), over FFI: on Windows
/// and Linux, where the runner exports it. Elsewhere, or from a runner built
/// before it, [available] is false and nothing else does anything.
abstract class CallClipNative {
  /// The runner's, behind a conditional import: it reaches `dart:ffi`,
  /// which the web build cannot compile.
  factory CallClipNative.platform() => platformCallClip();

  /// Nothing kept, anywhere: the web, macOS, the phones.
  const factory CallClipNative.none() = _NoCallClip;

  bool get available;

  /// Keeps [seconds] of the call (0 frees it), with the mic if [includeMic].
  void configure(int seconds, {required bool includeMic});

  /// Whether the ring takes in what the call plays.
  void setWriting(bool on);

  /// A copy of what the ring holds now; null when it holds nothing.
  CallClipAudio? snapshot();
}

class _NoCallClip implements CallClipNative {
  const _NoCallClip();

  @override
  bool get available => false;

  @override
  void configure(int seconds, {required bool includeMic}) {}

  @override
  void setWriting(bool on) {}

  @override
  CallClipAudio? snapshot() => null;
}
