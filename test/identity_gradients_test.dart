import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/participant_identity.dart';
import 'package:rift/presentation/theme/identity_gradients.dart';

/// An avatar's colour is an identity cue: it has to be the same every run, and
/// the same for everyone looking at the same person. That makes the seed →
/// gradient mapping worth pinning rather than trusting to a hash.
void main() {
  test('the same seed always gets the same gradient', () {
    final first = IdentityGradients.forSeed('user-abc-123');
    for (var i = 0; i < 50; i++) {
      expect(IdentityGradients.forSeed('user-abc-123'), same(first));
    }
  });

  test('the mapping is pinned, not just stable within a run', () {
    // Hard-coded expectations so a change to the algorithm shows up here
    // rather than as everyone's avatar silently changing colour.
    expect(IdentityGradients.forSeed('a'), IdentityGradients.all[1]);
    expect(IdentityGradients.forSeed('b'), IdentityGradients.all[2]);
    expect(IdentityGradients.forSeed('ab'), IdentityGradients.all[3]);
  });

  test('an empty seed falls back rather than throwing', () {
    expect(IdentityGradients.forSeed(''), IdentityGradients.all.first);
  });

  test('every gradient in the set gets used', () {
    // A mapping that collapses onto two of six would technically pass the
    // determinism tests while making avatars useless at telling people apart.
    final seen = <IdentityGradient>{};
    for (var i = 0; i < 200; i++) {
      seen.add(IdentityGradients.forSeed('user-$i'));
    }
    expect(seen.length, IdentityGradients.all.length);
  });

  test('unicode seeds resolve without throwing', () {
    for (final seed in ['🙂', 'Ünïcødé', '日本語', ' ']) {
      expect(IdentityGradients.all, contains(IdentityGradients.forSeed(seed)));
    }
  });

  // The gradient is a per-user concern, so it seeds from the user id — never
  // from a LiveKit identity, which carries a device segment and a screenshare
  // suffix. The voice grid used to seed from the raw identity, which is why a
  // participant's colour there disagreed with their own sidebar row.
  group('avatar seeds', () {
    const userId = 'd290f1ee-6c54-4b01-90e6-d701748f0851';
    const identities = [
      '$userId~a1b2c3d4',
      '$userId~e5f6a7b8',
      '$userId~a1b2c3d4_screenshare',
    ];

    test('one user has one colour across devices and their screenshare', () {
      final expected = IdentityGradients.forSeed(userId);
      for (final identity in identities) {
        expect(
          IdentityGradients.forSeed(ParticipantIdentity.userIdOf(identity)),
          same(expected),
          reason: '$identity should carry its owner\'s colour',
        );
      }
    });

    test('seeding from the raw identity would split one person up', () {
      // What the bug looked like: three connections belonging to one member,
      // wearing more than one colour between them.
      final seen = identities.map(IdentityGradients.forSeed).toSet();
      expect(seen.length, greaterThan(1));
    });
  });
}
