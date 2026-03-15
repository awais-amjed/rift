import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
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

  const VoiceStatsState({
    this.rttMs,
    this.jitterMs,
    this.packetLossPercent,
    this.quality = VoiceQuality.unknown,
    this.pingSamples = const [],
    this.isConnected = false,
  });

  VoiceStatsState copyWith({
    double? rttMs,
    double? jitterMs,
    double? packetLossPercent,
    VoiceQuality? quality,
    List<PingSample>? pingSamples,
    bool? isConnected,
  }) {
    return VoiceStatsState(
      rttMs: rttMs ?? this.rttMs,
      jitterMs: jitterMs ?? this.jitterMs,
      packetLossPercent: packetLossPercent ?? this.packetLossPercent,
      quality: quality ?? this.quality,
      pingSamples: pingSamples ?? this.pingSamples,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Polls the local participant's audio sender stats every second and tracks
/// ping history for the last 5 minutes.
class VoiceStatsCubit extends Cubit<VoiceStatsState> {
  final LiveKitCubit _livekitCubit;
  StreamSubscription<LiveKitState>? _lkSub;
  Timer? _timer;
  Room? _room;

  VoiceStatsCubit({required LiveKitCubit livekitCubit})
      : _livekitCubit = livekitCubit,
        super(const VoiceStatsState()) {
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
      final audioTrackPub =
          room.localParticipant?.audioTrackPublications.firstOrNull;
      final sender = audioTrackPub?.track?.sender;
      if (sender == null) return;

      final stats = await sender.getStats();
      if (isClosed) return;

      double? rttMs;
      double? jitterMs;
      double? packetLossPercent;

      // RTT from STUN candidate-pair
      for (final s in stats) {
        if (s.type == 'candidate-pair' && s.values['state'] == 'succeeded') {
          final rtt = s.values['currentRoundTripTime'] as num?;
          if (rtt != null) rttMs = rtt * 1000;
          break;
        }
      }

      // Jitter and packet loss from remote-inbound-rtp
      for (final s in stats) {
        if (s.type == 'remote-inbound-rtp' && s.values['kind'] == 'audio') {
          final jitter = s.values['jitter'] as num?;
          if (jitter != null) jitterMs = jitter * 1000;

          final fractionLost = s.values['fractionLost'] as num?;
          if (fractionLost != null) {
            packetLossPercent = (fractionLost * 100).clamp(0, 100).toDouble();
          }

          // Fallback RTT from this report if not found via candidate-pair
          if (rttMs == null) {
            final rtt = s.values['roundTripTime'] as num?;
            if (rtt != null) rttMs = rtt * 1000;
          }
          break;
        }
      }

      final quality = _calcQuality(rttMs, jitterMs, packetLossPercent);

      // Trim history to last 5 minutes and append new sample
      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(minutes: 5));
      final samples = List<PingSample>.from(state.pingSamples)
        ..removeWhere((s) => s.time.isBefore(cutoff));
      if (rttMs != null) {
        samples.add(PingSample(time: now, rttMs: rttMs));
      }

      emit(VoiceStatsState(
        rttMs: rttMs,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        quality: quality,
        pingSamples: samples,
        isConnected: true,
      ));
    } catch (_) {
      // Stats may be unavailable if track is not yet active; ignore.
    }
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
