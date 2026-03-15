import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../livekit/livekit_cubit.dart';

// ── State types ──────────────────────────────────────────────────────────────

enum VoiceQuality { unknown, good, fair, poor }

class PingSample {
  final DateTime time;
  final double rttMs;

  const PingSample({required this.time, required this.rttMs});
}

class VoiceStatsState {
  final double? rttMs;
  final double? jitterMs;
  final double? packetLossPercent;
  final VoiceQuality quality;
  final List<PingSample> pingSamples;
  final bool isConnected;
  final bool isAlone;

  const VoiceStatsState({
    this.rttMs,
    this.jitterMs,
    this.packetLossPercent,
    this.quality = VoiceQuality.unknown,
    this.pingSamples = const [],
    this.isConnected = false,
    this.isAlone = false,
  });

  VoiceStatsState copyWith({
    double? rttMs,
    double? jitterMs,
    double? packetLossPercent,
    VoiceQuality? quality,
    List<PingSample>? pingSamples,
    bool? isConnected,
    bool? isAlone,
  }) {
    return VoiceStatsState(
      rttMs: rttMs ?? this.rttMs,
      jitterMs: jitterMs ?? this.jitterMs,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      quality: quality ?? this.quality,
      pingSamples: pingSamples ?? this.pingSamples,
      isConnected: isConnected ?? this.isConnected,
      isAlone: isAlone ?? this.isAlone,
    );
  }
}

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Polls the local participant's audio sender stats every second and tracks
/// ping history for the last 5 minutes.
class VoiceStatsCubit extends Cubit<VoiceStatsState> {
  StreamSubscription<LiveKitState>? _lkSub;
  Timer? _timer;
  Room? _room;

  VoiceStatsCubit({required LiveKitCubit livekitCubit})
    : super(const VoiceStatsState()) {
    _lkSub = livekitCubit.stream.listen(_onLiveKitStateChanged);
    _onLiveKitStateChanged(livekitCubit.state);
  }

  void _onLiveKitStateChanged(LiveKitState lkState) {
    if (lkState.connectionState == LiveKitConnectionState.connected &&
        lkState.room != null) {
      _attachRoom(lkState.room!);
    } else {
      _detachRoom();
    }
  }

  void _attachRoom(Room room) {
    if (_room == room) return;
    _room = room;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
    _poll();
  }

  void _detachRoom() {
    _room = null;
    _timer?.cancel();
    _timer = null;
    emit(const VoiceStatsState());
  }

  Future<void> _poll() async {
    if (isClosed) return;
    final room = _room;
    if (room == null) return;

    try {
      // Gather sender stats — audio first, then video as fallback.
      List<StatsReport> senderStats = [];
      bool senderIsAudio = false;

      final local = room.localParticipant;
      if (local != null) {
        for (final pub in local.audioTrackPublications) {
          final s = pub.track?.sender;
          if (s != null) {
            senderStats = await s.getStats();
            senderIsAudio = true;
            break;
          }
        }
        if (senderStats.isEmpty) {
          for (final pub in local.videoTrackPublications) {
            final s = pub.track?.sender;
            if (s != null) {
              senderStats = await s.getStats();
              break;
            }
          }
        }
      }

      // Fall back to a remote participant's receiver for the candidate-pair RTT.
      List<StatsReport> receiverStats = [];
      if (senderStats.isEmpty) {
        outer:
        for (final remote in room.remoteParticipants.values) {
          for (final pub in [
            ...remote.audioTrackPublications,
            ...remote.videoTrackPublications,
          ]) {
            final receiver = pub.track?.receiver;
            if (receiver != null) {
              receiverStats = await receiver.getStats();
              if (receiverStats.isNotEmpty) break outer;
            }
          }
        }
      }

      if (isClosed) return;

      final allStats = [...senderStats, ...receiverStats];
      if (allStats.isEmpty) {
        emit(const VoiceStatsState(isConnected: true, isAlone: true));
        return;
      }

      double? rttMs;
      double? packetLossPercent;

      // RTT from STUN candidate-pair (connection-level, available regardless of mute)
      for (final s in allStats) {
        if (s.type == 'candidate-pair' && s.values['state'] == 'succeeded') {
          final rtt = s.values['currentRoundTripTime'] as num?;
          if (rtt != null) rttMs = rtt * 1000;
          break;
        }
      }

      // Packet loss from remote-inbound-rtp (per RTCP interval — already fresh)
      if (senderIsAudio) {
        for (final s in senderStats) {
          if (s.type == 'remote-inbound-rtp' && s.values['kind'] == 'audio') {
            final fractionLost = s.values['fractionLost'] as num?;
            if (fractionLost != null) {
              packetLossPercent =
                  (fractionLost * 100).clamp(0, 100).toDouble();
            }
            if (rttMs == null) {
              final rtt = s.values['roundTripTime'] as num?;
              if (rtt != null) rttMs = rtt * 1000;
            }
            break;
          }
        }
      }

      // Update ping history
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(minutes: 5));
      final samples = List<PingSample>.from(state.pingSamples)
        ..removeWhere((s) => s.time.isBefore(cutoff));
      if (rttMs != null) {
        samples.add(PingSample(time: now, rttMs: rttMs));
      }

      // Jitter = std-dev of the last 10 RTT samples.
      // Self-computed so it resets immediately — no cumulative EMA artifacts.
      final jitterMs = _calcJitter(samples);

      final quality = _calcQuality(rttMs, jitterMs, packetLossPercent);

      emit(
        VoiceStatsState(
          rttMs: rttMs,
          jitterMs: jitterMs,
          packetLossPercent: packetLossPercent,
          quality: quality,
          pingSamples: samples,
          isConnected: true,
          isAlone: false,
        ),
      );
    } catch (_) {
      // Stats may be unavailable if tracks are not yet active; ignore.
    }
  }

  /// Standard deviation of the last 10 RTT samples as a real-time jitter proxy.
  double? _calcJitter(List<PingSample> samples) {
    if (samples.length < 2) return null;
    final recent = samples.length > 10
        ? samples.sublist(samples.length - 10)
        : samples;
    final mean = recent.fold(0.0, (sum, s) => sum + s.rttMs) / recent.length;
    final variance =
        recent.fold(0.0, (sum, s) => sum + pow(s.rttMs - mean, 2)) /
        recent.length;
    return sqrt(variance);
  }

  VoiceQuality _calcQuality(
    double? rttMs,
    double? jitterMs,
    double? lossPercent,
  ) {
    if (rttMs == null) return VoiceQuality.unknown;
    if (rttMs < 100 && (jitterMs ?? 0) < 20 && (lossPercent ?? 0) < 1) {
      return VoiceQuality.good;
    }
    if (rttMs < 200 && (jitterMs ?? 0) < 50 && (lossPercent ?? 0) < 5) {
      return VoiceQuality.fair;
    }
    return VoiceQuality.poor;
  }

  @override
  Future<void> close() async {
    await _lkSub?.cancel();
    _timer?.cancel();
    return super.close();
  }
}
