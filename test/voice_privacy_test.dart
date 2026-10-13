import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_privacy.dart';

void main() {
  const alice = 'aaaa-1111';
  const bob = 'bbbb-2222';

  test('nobody hidden lets everyone subscribe', () {
    final result = VoicePrivacy.permissions(
      remoteIdentities: ['$alice~d1', '$bob~d2'],
      hiddenFrom: const [],
      nonMicTrackSids: const ['TR_cam'],
    );
    expect(result.allowAll, isTrue);
    expect(result.permissions, isEmpty);
  });

  test('a hidden person gets every track but the mic, on every connection', () {
    final result = VoicePrivacy.permissions(
      remoteIdentities: [
        '$alice~d1',
        '$bob~d2',
        '$bob~d3',
        '$bob~d2_screenshare',
      ],
      hiddenFrom: const [bob],
      nonMicTrackSids: const ['TR_cam'],
    );
    expect(result.allowAll, isFalse);
    final byId = {for (final p in result.permissions) p.participantIdentity: p};
    expect(byId.keys, hasLength(4));
    expect(byId['$alice~d1']!.allTracksAllowed, isTrue);
    for (final id in ['$bob~d2', '$bob~d3', '$bob~d2_screenshare']) {
      expect(byId[id]!.allTracksAllowed, isFalse, reason: id);
      expect(byId[id]!.allowedTrackSids, ['TR_cam'], reason: id);
    }
  });

  test('hiding from someone absent still switches to an allow-list', () {
    // They may join later; an allow-list is what keeps them out until then.
    final result = VoicePrivacy.permissions(
      remoteIdentities: ['$alice~d1'],
      hiddenFrom: const [bob],
      nonMicTrackSids: const [],
    );
    expect(result.allowAll, isFalse);
    expect(result.permissions.single.allTracksAllowed, isTrue);
  });
}
