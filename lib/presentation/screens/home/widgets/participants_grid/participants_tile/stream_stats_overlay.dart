import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

/// Displays stream statistics overlay for video tracks
class StreamStatsOverlay extends StatefulWidget {
  final VideoTrack track;

  const StreamStatsOverlay({super.key, required this.track});

  @override
  State<StreamStatsOverlay> createState() => _StreamStatsOverlayState();
}

class _StreamStatsOverlayState extends State<StreamStatsOverlay> {
  Timer? _statsTimer;
  Map<String, dynamic>? _prevStats;

  int? _width;
  int? _height;
  double? _fps;
  double? _bitrateKbps;
  int? _packetsLost;
  double? _jitterMs;
  String? _codec;
  double? _rttMs;
  int? _framesDropped;
  int? _pliCount;
  int? _nackCount;

  @override
  void initState() {
    super.initState();
    _startStatsPolling();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  void _startStatsPolling() {
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateStats();
    });
    // Get initial stats immediately
    _updateStats();
  }

  Future<void> _updateStats() async {
    if (!mounted) return;

    try {
      final receiver = widget.track.receiver;
      if (receiver == null) return;

      final rtcStats = await receiver.getStats();

      if (!mounted) return;

      // Extract candidate-pair RTT
      double? rttMs;
      for (final stats in rtcStats) {
        if (stats.type == 'candidate-pair' &&
            stats.values['state'] == 'succeeded') {
          final rtt = stats.values['currentRoundTripTime'] as num?;
          if (rtt != null) {
            rttMs = rtt * 1000;
          }
          break;
        }
      }

      // Look for inbound-rtp stats
      for (final stats in rtcStats) {
        if (stats.type == 'inbound-rtp' && stats.values['kind'] == 'video') {
          final values = stats.values;
          final timestamp = stats.timestamp;

          // Extract current values
          final bytesReceived = (values['bytesReceived'] as num?)?.toDouble();
          final framesDecoded = (values['framesDecoded'] as num?)?.toDouble();

          double? fps;
          double? bitrateKbps;

          // Calculate FPS and bitrate if we have previous stats
          if (_prevStats != null &&
              bytesReceived != null &&
              framesDecoded != null) {
            final prevTimestamp = _prevStats!['timestamp'] as double?;
            final prevBytesReceived = (_prevStats!['bytesReceived'] as num?)
                ?.toDouble();
            final prevFramesDecoded = (_prevStats!['framesDecoded'] as num?)
                ?.toDouble();

            if (prevTimestamp != null &&
                prevBytesReceived != null &&
                prevFramesDecoded != null) {
              // Timestamps are in microseconds, convert to milliseconds
              final dtMs = (timestamp - prevTimestamp) / 1000;

              if (dtMs > 0) {
                // Calculate bitrate
                final bytesDiff = bytesReceived - prevBytesReceived;
                if (bytesDiff > 0) {
                  final bitrateBps = (bytesDiff * 8 * 1000) / dtMs;
                  bitrateKbps = bitrateBps / 1000;
                }

                // Calculate FPS
                final framesDiff = framesDecoded - prevFramesDecoded;
                if (framesDiff > 0) {
                  fps = (framesDiff * 1000) / dtMs;
                }
              }
            }
          }

          // Fallback to the direct framesPerSecond value if calculation not ready
          fps ??= (values['framesPerSecond'] as num?)?.toDouble();

          // Store current stats for next calculation
          _prevStats = {
            'timestamp': timestamp,
            'bytesReceived': bytesReceived,
            'framesDecoded': framesDecoded,
          };

          if (mounted) {
            setState(() {
              _width = values['frameWidth'] as int?;
              _height = values['frameHeight'] as int?;
              _fps = fps;
              _bitrateKbps = bitrateKbps;
              _packetsLost = values['packetsLost'] as int?;
              final jitter = values['jitter'] as num?;
              _jitterMs = jitter != null ? jitter * 1000 : null;
              final mimeType = values['mimeType'] as String?;
              _codec = mimeType?.replaceFirst('video/', '');
              _rttMs = rttMs;
              _framesDropped = (values['framesDropped'] as num?)?.toInt();
              _pliCount = (values['pliCount'] as num?)?.toInt();
              _nackCount = (values['nackCount'] as num?)?.toInt();
            });
          }
          break;
        }
      }
    } catch (e) {
      // Track may not be subscribed yet or stats unavailable, ignore
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show if we have resolution info
    if (_width == null || _height == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow('Resolution', '${_width}x$_height'),
              if (_fps != null) ...[
                const SizedBox(height: 4),
                _buildStatRow('FPS', _fps!.toStringAsFixed(0)),
              ],
              if (_bitrateKbps != null) ...[
                const SizedBox(height: 4),
                _buildStatRow(
                  'Bitrate',
                  _bitrateKbps! >= 1000
                      ? '${(_bitrateKbps! / 1000).toStringAsFixed(1)} Mbps'
                      : '${_bitrateKbps!.toStringAsFixed(0)} Kbps',
                ),
              ],
              if (_rttMs != null) ...[
                const SizedBox(height: 4),
                _buildStatRow(
                  'RTT',
                  '${_rttMs!.toStringAsFixed(1)}ms',
                  isWarning: _rttMs! > 150,
                ),
              ],
              if (_jitterMs != null) ...[
                const SizedBox(height: 4),
                _buildStatRow(
                  'Jitter',
                  '${_jitterMs!.toStringAsFixed(1)}ms',
                  isWarning: _jitterMs! > 30,
                ),
              ],
              if (_packetsLost != null && _packetsLost! > 0) ...[
                const SizedBox(height: 4),
                _buildStatRow('Loss', '$_packetsLost pkts', isWarning: true),
              ],
              if (_framesDropped != null && _framesDropped! > 0) ...[
                const SizedBox(height: 4),
                _buildStatRow('Dropped', '$_framesDropped', isWarning: true),
              ],
              if (_pliCount != null && _pliCount! > 0) ...[
                const SizedBox(height: 4),
                _buildStatRow('PLI', '$_pliCount', isWarning: true),
              ],
              if (_nackCount != null && _nackCount! > 0) ...[
                const SizedBox(height: 4),
                _buildStatRow('NACK', '$_nackCount', isWarning: true),
              ],
              if (_codec != null) ...[
                const SizedBox(height: 4),
                _buildStatRow('Codec', _codec!.toUpperCase(), isMuted: true),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    String value, {
    bool isWarning = false,
    bool isMuted = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: isWarning
                ? Colors.orange.shade300
                : (isMuted ? Colors.white38 : Colors.white70),
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: isWarning
                ? Colors.orange
                : (isMuted ? Colors.white54 : Colors.white),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
