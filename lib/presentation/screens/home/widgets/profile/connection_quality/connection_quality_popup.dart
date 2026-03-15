import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../../../../../theme/custom_colors.dart';
import 'ping_graph.dart';

/// Popup panel shown above the connection quality indicator.
/// Shows ping, jitter, packet loss, and a 5-minute ping history graph.
class ConnectionQualityPopup extends StatelessWidget {
  const ConnectionQualityPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final bgColor = themeState.isDarkTheme
            ? const Color(0xFF1E1E21)
            : CustomColors.bgSecondaryLight;
        final borderColor = themeState.borderPrimary;

        return BlocBuilder<VoiceStatsCubit, VoiceStatsState>(
          builder: (context, stats) {
            return Container(
              width: 248,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Icon(
                          stats.isAlone
                              ? Icons.person_outline
                              : _qualityIcon(stats.quality),
                          size: 13,
                          color: stats.isAlone
                              ? themeState.textQuaternary
                              : _qualityColor(stats.quality),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VOICE CONNECTION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            color: themeState.textQuaternary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stats.isAlone
                          ? 'Waiting for others'
                          : _qualityLabel(stats.quality),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: stats.isAlone
                            ? themeState.textTertiary
                            : _qualityColor(stats.quality),
                      ),
                    ),

                    // Stats rows
                    if (stats.rttMs != null ||
                        stats.jitterMs != null ||
                        stats.packetLossPercent != null) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: borderColor),
                      const SizedBox(height: 10),
                      if (stats.rttMs != null)
                        _StatRow(
                          label: 'Ping',
                          value: '${stats.rttMs!.toStringAsFixed(0)} ms',
                          isWarning: stats.rttMs! > 200,
                          themeState: themeState,
                        ),
                      if (stats.jitterMs != null) ...[
                        const SizedBox(height: 6),
                        _StatRow(
                          label: 'Jitter',
                          value: '${stats.jitterMs!.toStringAsFixed(1)} ms',
                          isWarning: stats.jitterMs! > 50,
                          themeState: themeState,
                        ),
                      ],
                      if (stats.packetLossPercent != null) ...[
                        const SizedBox(height: 6),
                        _StatRow(
                          label: 'Packet Loss',
                          value:
                              '${stats.packetLossPercent!.toStringAsFixed(1)}%',
                          isWarning: stats.packetLossPercent! > 5,
                          themeState: themeState,
                        ),
                      ],
                    ],

                    // Ping history graph
                    if (stats.pingSamples.length >= 2) ...[
                      const SizedBox(height: 12),
                      Divider(height: 1, color: borderColor),
                      const SizedBox(height: 10),
                      Text(
                        'PING HISTORY · 5 MIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: themeState.textQuaternary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      PingGraph(samples: stats.pingSamples),
                    ],
                  ],
                ),
              ),
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
    VoiceQuality.unknown => 'Connecting…',
  };
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isWarning;
  final ThemeState themeState;

  const _StatRow({
    required this.label,
    required this.value,
    required this.isWarning,
    required this.themeState,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: themeState.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isWarning ? CustomColors.warning : themeState.textPrimary,
          ),
        ),
      ],
    );
  }
}


