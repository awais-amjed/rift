import 'package:flutter_test/flutter_test.dart';
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
}
