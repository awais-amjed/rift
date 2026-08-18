part of 'voice_stats_cubit.dart';

// ── State types ──────────────────────────────────────────────────────────────

class VoiceStatsState {
  final double? rttMs;
  final double? avgRttMs;
  final double? packetLossPercent;
  final VoiceQuality quality;
  final List<PingSample> pingSamples;
  final bool isConnected;
  final bool isAlone;

  const VoiceStatsState({
    this.rttMs,
    this.avgRttMs,
    this.packetLossPercent,
    this.quality = VoiceQuality.unknown,
    this.pingSamples = const [],
    this.isConnected = false,
    this.isAlone = false,
  });

  VoiceStatsState copyWith({
    double? rttMs,
    double? avgRttMs,
    double? packetLossPercent,
    VoiceQuality? quality,
    List<PingSample>? pingSamples,
    bool? isConnected,
    bool? isAlone,
  }) {
    return VoiceStatsState(
      rttMs: rttMs ?? this.rttMs,
      avgRttMs: avgRttMs ?? this.avgRttMs,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      quality: quality ?? this.quality,
      pingSamples: pingSamples ?? this.pingSamples,
      isConnected: isConnected ?? this.isConnected,
      isAlone: isAlone ?? this.isAlone,
    );
  }
}
