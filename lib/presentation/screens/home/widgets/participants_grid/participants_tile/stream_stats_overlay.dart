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
  int? _width;
  int? _height;
  String _type = 'Screen';

  @override
  void initState() {
    super.initState();
    _updateStats();
    widget.track.addListener(_updateStats);
  }

  @override
  void dispose() {
    widget.track.removeListener(_updateStats);
    super.dispose();
  }

  void _updateStats() {
    if (!mounted) return;

    setState(() {
      // Get video dimensions from the track
      final mediaStreamTrack = widget.track.mediaStreamTrack;
      final settings = mediaStreamTrack.getSettings();
      _width = settings['width'] as int?;
      _height = settings['height'] as int?;
    });
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
              const SizedBox(height: 4),
              _buildStatRow('Type', _type),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
