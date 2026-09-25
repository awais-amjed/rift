import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/services/video_stream_stats.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/media_colors.dart';

/// Live receive-side statistics for one video track, drawn over the tile.
///
/// Renders whatever `StreamStatsPoller` could work out; rows for values it
/// has no number for are simply absent. Pinning keeps the
/// overlay up when the tile's other controls fade — it persists in
/// [AppCubit] and is reported through [onPinnedChanged].
class StreamStatsOverlay extends StatefulWidget {
  final VideoStreamStats? stats;
  final ValueChanged<bool>? onPinnedChanged;

  const StreamStatsOverlay({
    super.key,
    required this.stats,
    this.onPinnedChanged,
  });

  @override
  State<StreamStatsOverlay> createState() => _StreamStatsOverlayState();
}

class _StreamStatsOverlayState extends State<StreamStatsOverlay> {
  /// Above these, the value is drawn in warning colours.
  static const _highPingMs = 150.0;
  static const _highJitterMs = 30.0;

  bool _pinned = false;

  @override
  void initState() {
    super.initState();
    _pinned = context.read<AppCubit>().state.statsOverlayPinned;
  }

  void _togglePinned() {
    setState(() => _pinned = !_pinned);
    context.read<AppCubit>().setStatsOverlayPinned(_pinned);
    widget.onPinnedChanged?.call(_pinned);
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    if (stats == null || !stats.hasResolution) return const SizedBox.shrink();

    final packetsLost = stats.packetsLost;
    final dropped = stats.framesDroppedPerSec;

    return Material(
      color: MediaColors.panel,
      borderRadius: BorderRadius.circular(K.radiusRow),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            _header(),
            _StatRow(label: 'Resolution', value: stats.resolutionLabel),
            if (stats.fps != null)
              _StatRow(label: 'FPS', value: stats.fps!.toStringAsFixed(0)),
            if (stats.bitrateLabel != null)
              _StatRow(label: 'Bitrate', value: stats.bitrateLabel!),
            if (stats.rttMs != null)
              _StatRow(
                label: 'Ping',
                value: '${stats.rttMs!.toStringAsFixed(1)}ms',
                isWarning: stats.rttMs! > _highPingMs,
              ),
            if (stats.jitterMs != null)
              _StatRow(
                label: 'Jitter',
                value: '${stats.jitterMs!.toStringAsFixed(1)}ms',
                isWarning: stats.jitterMs! > _highJitterMs,
              ),
            if (packetsLost != null && packetsLost > 0)
              _StatRow(
                label: 'Loss',
                value: '$packetsLost pkts',
                isWarning: true,
              ),
            if (dropped != null && dropped > 0)
              _StatRow(label: 'Dropped', value: '$dropped/s', isWarning: true),
            if (stats.codec != null)
              _StatRow(
                label: 'Codec',
                value: stats.codec!.toUpperCase(),
                isMuted: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Text(
          'Stats',
          style: AppText.roleChip.copyWith(color: MediaColors.onMediaTertiary),
        ),
        IconButton(
          onPressed: _togglePinned,
          icon: Icon(
            _pinned ? Icons.push_pin : Icons.push_pin_outlined,
            size: K.iconTiny,
            color: _pinned
                ? MediaColors.onMediaSecondary
                : MediaColors.onMediaQuaternary,
          ),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          style: const ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

/// One `Label: value` line of the overlay. [isWarning] marks a number that is
/// out of range; [isMuted] a purely informational one.
class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isWarning;
  final bool isMuted;

  const _StatRow({
    required this.label,
    required this.value,
    this.isWarning = false,
    this.isMuted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: AppText.label.copyWith(
            color: isWarning
                ? CustomColors.warning
                : (isMuted
                      ? MediaColors.onMediaQuaternary
                      : MediaColors.onMediaSecondary),
          ),
        ),
        Text(
          value,
          style: AppText.chip.copyWith(
            color: isWarning
                ? CustomColors.warning
                : (isMuted ? MediaColors.onMediaTertiary : MediaColors.onMedia),
          ),
        ),
      ],
    );
  }
}
