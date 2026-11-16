import 'package:equatable/equatable.dart';

/// The kinds of sound that can each play on a device of their own.
///
/// - [calls]: people's voices, sound shares and the soundboard — what the
///   call's own connection plays, and the clips pressed in it.
/// - [streams]: a watched screen share's sound, where Rift plays it itself
///   (`RustWatch.playsSound`). A share it cannot play that way comes through
///   the call, and so plays with [calls].
/// - [dings]: Rift's own cues — joining and leaving, push-to-talk, the ring,
///   a new message.
enum SoundKind { calls, streams, dings }

/// Where each [SoundKind] plays, when not on the main output. Per device, in
/// `AppState`, beside the main `outputDeviceId`.
///
/// A kind with no choice follows the main output, so somebody who never opens
/// the advanced pickers hears no difference, and changing the main output
/// moves everything that was never split off. [systemDefault] is a choice of
/// its own: "always the system's default", whatever the main output is.
class SoundOutputs extends Equatable {
  /// A choice meaning the system's default output. Not a device id any
  /// platform lists: WebRTC's are endpoint ids on Windows and sink names on
  /// Linux, and neither starts with a colon.
  static const String systemDefault = ':system-default';

  final String? calls;
  final String? streams;
  final String? dings;

  const SoundOutputs({this.calls, this.streams, this.dings});

  /// What was chosen for [kind]: a device id, [systemDefault], or null for
  /// "same as the output".
  String? choiceFor(SoundKind kind) => switch (kind) {
    SoundKind.calls => calls,
    SoundKind.streams => streams,
    SoundKind.dings => dings,
  };

  /// The device [kind] plays on, given the main [output]: an id, or null
  /// for the system default.
  String? deviceFor(SoundKind kind, String? output) =>
      switch (choiceFor(kind)) {
        null => output,
        systemDefault => null,
        final id => id,
      };

  /// Whether any kind has a choice of its own.
  bool get isSplit => calls != null || streams != null || dings != null;

  SoundOutputs withChoice(SoundKind kind, String? choice) => SoundOutputs(
    calls: kind == SoundKind.calls ? choice : calls,
    streams: kind == SoundKind.streams ? choice : streams,
    dings: kind == SoundKind.dings ? choice : dings,
  );

  factory SoundOutputs.fromJson(Map<String, dynamic> json) {
    String? read(String name) => switch (json[name]) {
      final String id when id.isNotEmpty => id,
      _ => null,
    };
    return SoundOutputs(
      calls: read('calls'),
      streams: read('streams'),
      dings: read('dings'),
    );
  }

  Map<String, dynamic> toJson() => {
    'calls': calls,
    'streams': streams,
    'dings': dings,
  };

  @override
  List<Object?> get props => [calls, streams, dings];
}
