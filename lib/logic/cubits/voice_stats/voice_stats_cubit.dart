import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../data/classes/ping_sample.dart';
import '../../../data/enums/voice_quality.dart';
import '../../../data/participant_identity.dart';
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

      // Being alone is about the room, not about the stats. It used to mean
      // "no media to measure", which is also what a call where everybody
      // happens to be muted looks like — so two people sitting quietly, one of
      // them watching the other's screen, were both told they were waiting for
      // somebody to arrive.
      //
      // It no longer stops the measuring either. The connection to the server
      // is the same connection whether or not anybody else has arrived, and
      // "is my network alright?" is a question people ask *before* a call as
      // much as during one.
      final alone = _isAlone(room);

      // Media first, and the transports only when the media had nothing to
      // say — which is a call where nobody is talking, not a call in trouble.
      var rttMs =
          _iceRtt([senderStats, receiverStats]) ?? _rtcpRtt(senderStats);
      rttMs ??= _iceRtt([await _collectTransportStats(room)]);
      if (isClosed) return;
      final packetLossPercent = _readPacketLoss(senderStats);

      // Only record a genuinely new measurement. currentRoundTripTime is
      // refreshed by ICE consent checks every few seconds while this polls
      // every second, so appending unconditionally filled the history with
      // repeats of one reading and gave the graph a resolution it never had.
      if (rttMs != null && (samples.isEmpty || samples.last.rttMs != rttMs)) {
        samples.add(PingSample(time: now, rttMs: rttMs));
      }

      final avgRttMs = _averageRtt(samples);

      emit(
        VoiceStatsState(
          rttMs: rttMs,
          avgRttMs: avgRttMs,
          packetLossPercent: packetLossPercent,
          quality: _calcQuality(rttMs, packetLossPercent),
          pingSamples: samples,
          isConnected: true,
          isAlone: alone,
        ),
      );
    } catch (_) {
      // Stats may be unavailable if tracks are not yet active; ignore.
    }
  }

  /// Whether anybody else is here. Shares are left out: a screen share is a
  /// second connection of somebody already counted, and a room containing
  /// only your own share is a room you are alone in.
  bool _isAlone(Room room) => !room.remoteParticipants.values.any(
    (p) => !ParticipantIdentity.isShare(p.identity),
  );

  /// Stats for the transports themselves.
  ///
  /// The two above can both come back empty in an ordinary call: nothing is
  /// published while the microphone is muted, and nothing is received while
  /// everybody else's is. The peer connections are up regardless — they carry
  /// the signalling, and their ICE candidate pairs are being probed the whole
  /// time — so this is where a ping comes from when no media is moving.
  Future<List<StatsReport>> _collectTransportStats(Room room) async {
    // ignore: invalid_use_of_internal_member
    final engine = room.engine;
    for (final transport in [
      // ignore: invalid_use_of_internal_member
      engine.publisher,
      // ignore: invalid_use_of_internal_member
      engine.subscriber,
    ]) {
      final pc = transport?.pc;
      if (pc == null) continue;
      final stats = await pc.getStats();
      if (stats.isNotEmpty) return stats;
    }
    return const [];
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

  /// Round-trip time in milliseconds from an ICE candidate pair.
  ///
  /// LiveKit runs a publisher and a subscriber peer connection, each with its
  /// own candidate pair and its own round-trip time. Searching them in a fixed
  /// order keeps the reading on a single connection instead of flipping
  /// between two different numbers as tracks come and go.
  double? _iceRtt(List<List<StatsReport>> sources) {
    for (final reports in sources) {
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
    return null;
  }

  /// The RTCP round trip, which only exists while we are sending.
  double? _rtcpRtt(List<StatsReport> sender) {
    for (final s in sender) {
      if (s.type != 'remote-inbound-rtp') continue;
      final rtt = s.values['roundTripTime'] as num?;
      if (rtt != null) return rtt * 1000;
    }
    return null;
  }

  /// Mean of the last ten round-trip readings, for display alongside the
  /// current one. Grading does not use it — see [_calcQuality].
  double? _averageRtt(List<PingSample> samples) {
    if (samples.isEmpty) return null;
    final recent = samples.length > 10
        ? samples.sublist(samples.length - 10)
        : samples;
    return recent.fold(0.0, (sum, s) => sum + s.rttMs) / recent.length;
  }

  /// Outbound packet loss, as a percentage.
  ///
  /// Null while the mic is muted: with no RTP going out there are no receiver
  /// reports coming back and nothing to measure. See [_calcQuality] for what
  /// that null then counts as.
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

  /// Grades the call on round-trip time and packet loss.
  ///
  /// Jitter used to count here and no longer does. RTP jitter is an
  /// inter-arrival measure, and push-to-talk means remote audio stops dead
  /// whenever somebody releases their key — the gap across a pause folds
  /// straight into the estimate, so it grew with how long people stayed quiet
  /// rather than with anything about the network. A LAN with a 1ms ping still
  /// read tens of milliseconds and graded Poor.
  ///
  /// Grading reads the latest measurement, so the badge follows the connection
  /// as it changes rather than lagging behind a run of older readings.
  /// [VoiceStatsState.avgRttMs] is there to be shown, not to grade on.
  ///
  /// Unmeasurable loss counts as none. It is null whenever the mic is muted,
  /// which under push-to-talk is most of the time, so the alternative — refuse
  /// to grade without it — would leave the badge stuck below its real grade
  /// for exactly the users who rely on it. Round-trip time is measured either
  /// way, and it is the reading that moves first when a connection turns bad;
  /// loss sharpens the grade when it is there rather than gating it.
  VoiceQuality _calcQuality(double? rttMs, double? lossPercent) {
    if (rttMs == null) return VoiceQuality.unknown;
    final loss = lossPercent ?? 0;
    if (rttMs < 50 && loss < 0.5) return VoiceQuality.excellent;
    if (rttMs < 100 && loss < 1) return VoiceQuality.good;
    if (rttMs < 200 && loss < 5) return VoiceQuality.fair;
    return VoiceQuality.poor;
  }

  @override
  Future<void> close() async {
    await _lkSub?.cancel();
    _timer?.cancel();
    return super.close();
  }
}
