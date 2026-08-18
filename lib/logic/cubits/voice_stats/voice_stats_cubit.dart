import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/ping_sample.dart';
import '../../../data/enums/voice_quality.dart';
import '../livekit/livekit_cubit.dart';

part 'voice_stats_state.dart';

// ── Cubit ────────────────────────────────────────────────────────────────────

/// Polls the call's transport stats every second and tracks ping history for
/// the last 5 minutes.
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
      final senderStats = await _collectSenderStats(room);
      final receiverStats = await _collectReceiverStats(room);

      if (isClosed) return;

      final now = DateTime.now();
      final cutoff = now.subtract(const Duration(minutes: 5));
      final samples = List<PingSample>.from(state.pingSamples)
        ..removeWhere((s) => s.time.isBefore(cutoff));

      if (senderStats.isEmpty && receiverStats.isEmpty) {
        // Drop the live readings but keep the history. The graph covers five
        // minutes, and a gap in the stats is not a reason to throw away what
        // came before it — this used to reset and take the graph with it.
        emit(
          VoiceStatsState(
            pingSamples: samples,
            isConnected: true,
            isAlone: true,
          ),
        );
        return;
      }

      final rttMs = _readRtt(senderStats, receiverStats);
      final jitterMs = _readJitter(senderStats, receiverStats);
      final packetLossPercent = _readPacketLoss(senderStats);

      // Only record a genuinely new measurement. currentRoundTripTime is
      // refreshed by ICE consent checks every few seconds while this polls
      // every second, so appending unconditionally filled the history with
      // repeats of one reading and gave the graph a resolution it never had.
      if (rttMs != null && (samples.isEmpty || samples.last.rttMs != rttMs)) {
        samples.add(PingSample(time: now, rttMs: rttMs));
      }

      emit(
        VoiceStatsState(
          rttMs: rttMs,
          jitterMs: jitterMs,
          packetLossPercent: packetLossPercent,
          quality: _calcQuality(rttMs, jitterMs, packetLossPercent),
          pingSamples: samples,
          isConnected: true,
          isAlone: false,
        ),
      );
    } catch (_) {
      // Stats may be unavailable if tracks are not yet active; ignore.
    }
  }

  /// Stats for what we are publishing — audio first, video as a fallback.
  Future<List<StatsReport>> _collectSenderStats(Room room) async {
    final local = room.localParticipant;
    if (local == null) return const [];
    for (final pub in [
      ...local.audioTrackPublications,
      ...local.videoTrackPublications,
    ]) {
      final sender = pub.track?.sender;
      if (sender == null) continue;
      final stats = await sender.getStats();
      if (stats.isNotEmpty) return stats;
    }
    return const [];
  }

  /// Stats for what we are receiving.
  ///
  /// Collected even while we are publishing, because push-to-talk leaves the
  /// mic muted most of the time and every outbound measurement dries up the
  /// moment we stop sending — no RTP going out means no RTCP receiver reports
  /// coming back.
  Future<List<StatsReport>> _collectReceiverStats(Room room) async {
    for (final remote in room.remoteParticipants.values) {
      for (final pub in [
        ...remote.audioTrackPublications,
        ...remote.videoTrackPublications,
      ]) {
        final receiver = pub.track?.receiver;
        if (receiver == null) continue;
        final stats = await receiver.getStats();
        if (stats.isNotEmpty) return stats;
      }
    }
    return const [];
  }

  /// Round-trip time in milliseconds, preferring the publishing connection.
  ///
  /// LiveKit runs a publisher and a subscriber peer connection, each with its
  /// own ICE candidate pair and its own round-trip time. Searching one and
  /// then the other in a fixed order keeps the reading on a single connection
  /// instead of flipping between two different numbers as tracks come and go.
  double? _readRtt(List<StatsReport> sender, List<StatsReport> receiver) {
    for (final reports in [sender, receiver]) {
      for (final s in reports) {
        if (s.type != 'candidate-pair') continue;
        if (s.values['state'] != 'succeeded') continue;
        final rtt = s.values['currentRoundTripTime'] as num?;
        // Keep looking rather than giving up here. A succeeded pair with no
        // measurement is not an answer, and a report usually holds several.
        if (rtt == null) continue;
        return rtt * 1000;
      }
    }
    // No usable ICE measurement — fall back to the RTCP round trip, which
    // only exists while we are sending.
    for (final s in sender) {
      if (s.type != 'remote-inbound-rtp') continue;
      final rtt = s.values['roundTripTime'] as num?;
      if (rtt != null) return rtt * 1000;
    }
    return null;
  }

  /// Real RTP jitter, in milliseconds.
  ///
  /// This used to be the standard deviation of the last ten round-trip
  /// samples, which measures ping variability rather than jitter and swings
  /// far wider. One stale reading stepping from 1ms to 40ms produced about
  /// 12ms of it — enough to fail the 20ms bar on a link whose ping was 1ms,
  /// and it stayed in the window for the next ten polls. WebRTC reports the
  /// real quantity, and the thresholds were written for that.
  double? _readJitter(List<StatsReport> sender, List<StatsReport> receiver) {
    // How our audio lands at the server, reported back over RTCP.
    for (final s in sender) {
      if (s.type != 'remote-inbound-rtp') continue;
      if (s.values['kind'] != 'audio') continue;
      final jitter = s.values['jitter'] as num?;
      if (jitter != null) return jitter * 1000;
    }
    // Otherwise how audio lands here, which stays measurable while muted for
    // as long as somebody else is talking.
    for (final s in receiver) {
      if (s.type != 'inbound-rtp') continue;
      if (s.values['kind'] != 'audio') continue;
      final jitter = s.values['jitter'] as num?;
      if (jitter != null) return jitter * 1000;
    }
    return null;
  }

  /// Outbound packet loss, as a percentage.
  ///
  /// Null while the mic is muted: with no RTP going out there are no receiver
  /// reports coming back and nothing to measure. [_calcQuality] treats that as
  /// no evidence of loss rather than as zero loss observed.
  double? _readPacketLoss(List<StatsReport> sender) {
    for (final s in sender) {
      if (s.type != 'remote-inbound-rtp') continue;
      if (s.values['kind'] != 'audio') continue;
      final fractionLost = s.values['fractionLost'] as num?;
      if (fractionLost == null) continue;
      return (fractionLost * 100).clamp(0, 100).toDouble();
    }
    return null;
  }

  /// Grades the call.
  ///
  /// The jitter bars are in real RTP jitter now rather than round-trip
  /// standard deviation, so they mean what they look like they mean. Excellent
  /// exists so a 1ms link and a 90ms one stop sharing a label.
  VoiceQuality _calcQuality(
    double? rttMs,
    double? jitterMs,
    double? lossPercent,
  ) {
    if (rttMs == null) return VoiceQuality.unknown;
    final jitter = jitterMs ?? 0;
    final loss = lossPercent ?? 0;
    if (rttMs < 50 && jitter < 10 && loss < 0.5) return VoiceQuality.excellent;
    if (rttMs < 100 && jitter < 20 && loss < 1) return VoiceQuality.good;
    if (rttMs < 200 && jitter < 50 && loss < 5) return VoiceQuality.fair;
    return VoiceQuality.poor;
  }

  @override
  Future<void> close() async {
    await _lkSub?.cancel();
    _timer?.cancel();
    return super.close();
  }
}
