import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/services/call_volume.dart';
import '../../../../common/volume_slider.dart';

/// The bare track for how loud somebody is in your ears — no label, no
/// readout — so the menu can stack it under its heading and a profile can
/// sit it at the end of a row.
///
/// Disabled while they're locally muted, where a position would be a volume
/// with no effect.
class ParticipantVolumeSlider extends StatelessWidget {
  /// A live LiveKit identity, or a bare user id when they aren't connected —
  /// [LiveKitCubit.setParticipantVolume] accepts either and stores the setting
  /// per user.
  final String target;

  final bool isMuted;
  final double volume;

  /// Where the new volume goes. Defaults to the participant's own — a shared
  /// track passes its own, so that turning the music down does not turn its
  /// owner down with it.
  final ValueChanged<double>? onChanged;

  /// A voice or a shared sound goes up to [CallVolume.max]; a soundboard,
  /// played here by a player that stops at 1, passes 1.
  final double? max;

  const ParticipantVolumeSlider({
    super.key,
    required this.target,
    required this.isMuted,
    required this.volume,
    this.onChanged,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    return VolumeSlider(
      value: isMuted ? 0 : volume,
      max: max ?? CallVolume.max,
      onChanged: isMuted
          ? null
          : (value) {
              final handler = onChanged;
              if (handler != null) {
                handler(value);
                return;
              }
              context.read<LiveKitCubit>().setParticipantVolume(target, value);
            },
    );
  }

  /// The readout beside it: an em dash while muted rather than 0%, which
  /// would look like a volume you'd chosen.
  static String readout({required bool isMuted, required double volume}) =>
      isMuted ? '—' : '${(volume * 100).round()}%';
}
