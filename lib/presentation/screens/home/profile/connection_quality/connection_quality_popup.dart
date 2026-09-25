import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/livekit_node.dart';
import '../../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/voice_stats/voice_stats_cubit.dart';
import '../../../../common/popover_surface.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/custom_colors.dart';
import '../../../../theme/theme_context.dart';
import 'connection_quality_style.dart';
import 'ping_graph.dart';

/// Popup panel shown above the connection quality indicator.
///
/// Ping, average ping, packet loss, a 5-minute ping history graph — and which
/// **region** the call is on, when the server has more than one. Without it a
/// number is a number: a ping of 240 ms means something quite different
/// depending on whether you are in the region next door or the one across an
/// ocean, and until now nothing in Rift said which.
///
/// Matched by address rather than by name, because the address is what the
/// token carried. An operator renaming a region mid-call then shows the new
/// name against the same connection, which is right — it is the same box.
class ConnectionQualityPopup extends StatelessWidget {
  const ConnectionQualityPopup({super.key});

  /// The name of the region this call is on, or null when the server has
  /// only one — where naming it would be answering a question nobody has.
  String? _region(BuildContext context) {
    final url = context.read<LiveKitCubit>().state.connectedLivekitUrl;
    if (url == null) return null;

    final nodes =
        context.read<ServerCubit>().state.selectedServer?.livekitNodes ??
        const <LiveKitNode>[];
    if (nodes.length < 2) return null;

    for (final node in nodes) {
      if (node.url == url) return node.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final borderColor = themeState.borderPrimary;

    return BlocBuilder<VoiceStatsCubit, VoiceStatsState>(
      builder: (context, stats) {
        // Whether there is a reading at all. Being the only one here is no
        // longer a reason not to have one — the connection to the server
        // is the same connection either way.
        final measured = stats.rttMs != null;

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
                      measured
                          ? ConnectionQualityStyle.icon(stats.quality)
                          : Icons.person_outline,
                      size: 13,
                      color: measured
                          ? ConnectionQualityStyle.color(
                              stats.quality,
                              themeState,
                            )
                          : themeState.textQuaternary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'VOICE CONNECTION',
                      style: AppText.sectionLabel.copyWith(
                        color: themeState.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  measured
                      ? ConnectionQualityStyle.label(
                          stats.quality,
                          unknown: 'Connecting…',
                        )
                      : (stats.isAlone ? 'Waiting for others' : 'Connecting…'),
                  style: AppText.sectionTitle.copyWith(
                    color: measured
                        ? ConnectionQualityStyle.color(
                            stats.quality,
                            themeState,
                          )
                        : themeState.textTertiary,
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
                    ),
                  if (stats.avgRttMs != null) ...[
                    const SizedBox(height: 6),
                    _StatRow(
                      label: 'Average ping',
                      value: '${stats.avgRttMs!.toStringAsFixed(0)} ms',
                      isWarning: stats.avgRttMs! > 200,
                    ),
                  ],
                  if (stats.packetLossPercent != null) ...[
                    const SizedBox(height: 6),
                    _StatRow(
                      label: 'Packet loss',
                      value: '${stats.packetLossPercent!.toStringAsFixed(1)}%',
                      isWarning: stats.packetLossPercent! > 5,
                    ),
                  ],
                  if (_region(context) case final region?) ...[
                    const SizedBox(height: 6),
                    _StatRow(label: 'Region', value: region, isWarning: false),
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
                      color: themeState.textTertiary,
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
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isWarning;
  const _StatRow({
    required this.label,
    required this.value,
    required this.isWarning,
  });

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppText.secondary.copyWith(
            color: themeState.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: AppText.secondaryStrong.copyWith(
            color: isWarning
                ? themeState.statusInk(CustomColors.warning)
                : themeState.textPrimary,
          ),
        ),
      ],
    );
  }
}
