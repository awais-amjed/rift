import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show StatsReport;

/// Notices a phone's share that viewers cannot see, which nothing else says.
///
/// When a phone cannot open the encoder for its share's codec, libwebrtc moves
/// the sender to another codec by itself and goes on sending. The track is still
/// published as the first one, so viewers stay black, and they stay black after
/// an encoder comes free: only a new share mends it (`CALLS.md`, *A phone's
/// share*). The frame counts look healthy throughout, so what gives it away is
/// the codec itself.
///
/// A phone's share is usually of another app, so the person has often left Rift
/// by then. [onFailed] runs at once, for what can be seen from outside, and
/// [onSeen] waits until they are looking, so a toast is not spent on nobody.
class PhoneEncoderWatch {
  static const _every = Duration(seconds: 3);

  final Future<bool> Function() _leftItsCodec;
  final bool Function() _stillSharing;
  final bool Function() _inFront;
  final VoidCallback _onFailed;
  final VoidCallback _onSeen;

  Timer? _timer;
  bool _failed = false;

  PhoneEncoderWatch({
    required Future<bool> Function() leftItsCodec,
    required bool Function() stillSharing,
    required bool Function() inFront,
    required VoidCallback onFailed,
    required VoidCallback onSeen,
  }) : _leftItsCodec = leftItsCodec,
       _stillSharing = stillSharing,
       _inFront = inFront,
       _onFailed = onFailed,
       _onSeen = onSeen;

  /// Whether a sender's [reports] show it sending something other than [codec],
  /// the one its track was published in (`h264`). Unknown either way is not a
  /// failure.
  static bool leftItsCodec(String codec, Iterable<StatsReport> reports) {
    if (codec.isEmpty) return false;
    final published = 'video/${codec.toLowerCase()}';
    for (final report in reports) {
      if (report.type != 'outbound-rtp') continue;
      final codecId = report.values['codecId'];
      final sent = reports.where((r) => r.id == codecId).firstOrNull;
      final mime = sent?.values['mimeType'] as String?;
      if (mime != null && mime.toLowerCase() != published) return true;
    }
    return false;
  }

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_every, (_) => _check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (!_stillSharing()) return stop();
    if (!_failed) {
      final failed = await _leftItsCodec();
      // Stopped while asking, or another tick got there first.
      if (_timer == null || _failed || !failed) return;
      _failed = true;
      _onFailed();
    }
    if (!_inFront()) return;
    stop();
    _onSeen();
  }
}
