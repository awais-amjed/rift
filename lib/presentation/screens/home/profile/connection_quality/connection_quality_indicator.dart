import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/enums/voice_quality.dart';
import '../../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../../../../theme/custom_colors.dart';
import 'connection_quality_popup.dart';

/// Compact signal-strength line rendered inside the user dock (under the
/// display name) while in a voice channel. Tapping it opens a popup with
/// detailed voice connection stats.
class ConnectionQualityIndicator extends StatefulWidget {
  const ConnectionQualityIndicator({super.key});

  @override
  State<ConnectionQualityIndicator> createState() =>
      _ConnectionQualityIndicatorState();
}

class _ConnectionQualityIndicatorState
    extends State<ConnectionQualityIndicator> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _entry;

  void _toggle() {
    if (_entry != null) {
      _dismiss();
    } else {
      _show();
    }
  }

  void _show() {
    final renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final screenWidth = MediaQuery.of(context).size.width;

    // Popup width — clamp so it doesn't bleed off screen
    const popupWidth = 248.0;
    final left = (offset.dx + popupWidth > screenWidth)
        ? screenWidth - popupWidth - 8
        : offset.dx;

    // Anchor the popup bottom just above the indicator bar
    final bottomOffset = MediaQuery.of(context).size.height - offset.dy + 4;

    // Capture blocs from current context before entering overlay
    final voiceStatsCubit = context.read<VoiceStatsCubit>();
    final themeCubit = context.read<ThemeCubit>();

    _entry = OverlayEntry(
      builder: (overlayCtx) => Stack(
        children: [
          // Full-screen dismiss barrier
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _dismiss,
            ),
          ),
          // Popup anchored above the indicator
          Positioned(
            left: left,
            bottom: bottomOffset,
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: voiceStatsCubit),
                BlocProvider.value(value: themeCubit),
              ],
              child: const ConnectionQualityPopup(),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_entry!);
  }

  void _dismiss() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LiveKitCubit, LiveKitState>(
      buildWhen: (prev, curr) => prev.connectionState != curr.connectionState,
      builder: (context, lkState) {
        if (lkState.connectionState != LiveKitConnectionState.connected) {
          return const SizedBox.shrink();
        }

        return BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return BlocBuilder<VoiceStatsCubit, VoiceStatsState>(
              builder: (context, stats) {
                if (stats.isAlone) _dismiss();

                final color = _qualityColor(stats.quality);
                final label = stats.isAlone
                    ? 'Waiting for others…'
                    : stats.rttMs != null
                    ? '${stats.rttMs!.toStringAsFixed(0)} ms · ${_qualityLabel(stats.quality)}'
                    : 'Connecting…';

                return Material(
                  key: _buttonKey,
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: themeState.bgHover,
                    onTap: stats.isAlone ? null : _toggle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          stats.isAlone
                              ? Icons.person_outline
                              : _qualityIcon(stats.quality),
                          size: 11,
                          color: stats.isAlone
                              ? themeState.textQuaternary
                              : color,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.textTertiary,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  IconData _qualityIcon(VoiceQuality quality) => switch (quality) {
    VoiceQuality.good => Icons.signal_cellular_4_bar,
    VoiceQuality.fair => Icons.signal_cellular_alt,
    VoiceQuality.poor => Icons.signal_cellular_0_bar,
    VoiceQuality.unknown => Icons.signal_cellular_null,
  };

  Color _qualityColor(VoiceQuality quality) => switch (quality) {
    VoiceQuality.good => CustomColors.success,
    VoiceQuality.fair => CustomColors.warning,
    VoiceQuality.poor => CustomColors.error,
    VoiceQuality.unknown => Colors.grey,
  };

  String _qualityLabel(VoiceQuality quality) => switch (quality) {
    VoiceQuality.good => 'Good',
    VoiceQuality.fair => 'Fair',
    VoiceQuality.poor => 'Poor',
    VoiceQuality.unknown => 'No data',
  };
}
