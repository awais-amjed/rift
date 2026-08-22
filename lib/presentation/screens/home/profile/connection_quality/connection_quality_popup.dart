import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../../../../common/popover_surface.dart';
import '../../../../theme/custom_colors.dart';
import 'connection_quality_style.dart';
import 'ping_graph.dart';
import '../../../../theme/app_text.dart';

/// Popup panel shown above the connection quality indicator.
/// Shows ping, average ping, packet loss, and a 5-minute ping history graph.
class ConnectionQualityPopup extends StatelessWidget {
  const ConnectionQualityPopup({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final borderColor = themeState.borderPrimary;

        return BlocBuilder<VoiceStatsCubit, VoiceStatsState>(
          builder: (context, stats) {
            // The shared surface, not a hand-rolled copy of it: this is opened
            // into the Overlay, so it needs the Material that carries with it,
            // and it now picks up the popover radius and shadow everything
            // else floating uses.
            return SizedBox(
              width: 248,
              child: PopoverSurface(
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
                              : ConnectionQualityStyle.icon(stats.quality),
                          size: 13,
                          color: stats.isAlone
                              ? themeState.textQuaternary
                              : ConnectionQualityStyle.color(
                                  stats.quality,
                                  themeState,
                                ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VOICE CONNECTION',
                          style: AppText.sectionLabel.copyWith(
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
                          : ConnectionQualityStyle.label(
                              stats.quality,
                              unknown: 'Connecting…',
                            ),
                      style: AppText.row.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: stats.isAlone
                            ? themeState.textTertiary
                            : ConnectionQualityStyle.color(
                                stats.quality,
                                themeState,
                              ),
                      ),
                    ),

                    // Stats rows
                    if (stats.rttMs != null ||
                        stats.avgRttMs != null ||
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
                      if (stats.avgRttMs != null) ...[
                        const SizedBox(height: 6),
                        _StatRow(
                          label: 'Average Ping',
                          value: '${stats.avgRttMs!.toStringAsFixed(0)} ms',
                          isWarning: stats.avgRttMs! > 200,
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
                        style: AppText.sectionLabel.copyWith(
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
          style: AppText.secondary.copyWith(
            fontSize: 12,
            color: themeState.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: AppText.secondary.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isWarning ? CustomColors.warning : themeState.textPrimary,
          ),
        ),
      ],
    );
  }
}
