// RIFT PATCH: this file. See third_party/livekit_client/RIFT_PATCHES.md.
import 'package:sdp_transform/sdp_transform.dart' as sdp_transform;

/// [answer] with `stereo=1` on Opus for every audio section the server's
/// [offer] marks `sprop-stereo=1`.
///
/// WebRTC sizes its Opus decoder from the receiver's own parameters, so an
/// answer without `stereo=1` decodes a stereo track into one channel. The
/// server marks a track whose publisher listed `TF_STEREO`; the JS SDK answers
/// it the same way (`ensureAudioNackAndStereo`).
String? addStereoToAnswer({required String? offer, required String? answer}) {
  if (offer == null || answer == null) return answer;
  final stereoMids = <String>{};
  for (final media in _media(sdp_transform.parse(offer))) {
    if (media['type'] != 'audio') continue;
    final fmtps = (media['fmtp'] as List?) ?? const [];
    if (fmtps.any((f) => _params(f).contains('sprop-stereo=1'))) {
      stereoMids.add('${media['mid']}');
    }
  }
  if (stereoMids.isEmpty) return answer;

  final parsed = sdp_transform.parse(answer);
  for (final media in _media(parsed)) {
    if (media['type'] != 'audio' || !stereoMids.contains('${media['mid']}')) {
      continue;
    }
    final opus = ((media['rtp'] as List?) ?? const [])
        .where((r) => '${r['codec']}'.toLowerCase() == 'opus')
        .map((r) => r['payload'])
        .toSet();
    for (final fmtp in (media['fmtp'] as List?) ?? const []) {
      if (opus.contains(fmtp['payload']) && !_params(fmtp).contains('stereo=1')) {
        fmtp['config'] = '${fmtp['config']};stereo=1';
      }
    }
  }
  return sdp_transform.write(parsed, null);
}

List _media(Map<String, dynamic> sdp) => (sdp['media'] as List?) ?? const [];

Iterable<String> _params(dynamic fmtp) =>
    '${fmtp['config'] ?? ''}'.split(';').map((p) => p.trim());
