import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// The call as this client heard it, taken when the clip shortcut was
/// pressed: interleaved 16-bit samples, waiting for the trim view.
class CallClipAudio extends Equatable {
  /// Which press this was; two presses never share one.
  final int id;
  final Int16List pcm;
  final int rate;
  final int channels;

  /// When the shortcut was pressed.
  final DateTime at;

  const CallClipAudio({
    required this.id,
    required this.pcm,
    required this.rate,
    required this.channels,
    required this.at,
  });

  int get frames => channels == 0 ? 0 : pcm.length ~/ channels;

  Duration get duration =>
      Duration(microseconds: rate == 0 ? 0 : frames * 1000000 ~/ rate);

  /// The length in whole seconds, as the call is told it.
  int get seconds => (duration.inMilliseconds / 1000).round();

  /// Every field, as every model here compares. Cheap all the same: a clip
  /// carries the same sample list through every copy of the call's state,
  /// and Equatable stops at an identical one before reading any samples.
  @override
  List<Object?> get props => [id, pcm, rate, channels, at];
}
