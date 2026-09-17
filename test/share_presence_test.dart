import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/share_presence.dart';

/// A stand-in participant: an identity, and whether it publishes a screen on
/// its own connection (which is what a phone does).
class P {
  final String identity;
  final bool publishesScreen;

  const P(this.identity, {this.publishesScreen = false});
}

SharePresence presence(List<P> participants) => sharePresenceOf(
  participants,
  identityOf: (p) => p.identity,
  publishesScreenshare: (p) => p.publishesScreen,
);

void main() {
  test('a share is credited to the person, not to its connection', () {
    final result = presence([
      const P('alice~dev1'),
      const P('alice~dev1_screenshare'),
    ]);

    expect(result.sharesScreen('alice'), isTrue);
    expect(result.sharesSound('alice'), isFalse);
  });

  test('a shared track is its own kind of sharing', () {
    final result = presence([
      const P('bob~dev1'),
      const P('bob~dev1_soundshare'),
    ]);

    expect(result.sharesSound('bob'), isTrue);
    expect(result.sharesScreen('bob'), isFalse);
  });

  // A phone publishes its screen on the connection it already has, so there is
  // no second identity to notice.
  test('a phone sharing its screen is still sharing', () {
    final result = presence([const P('carol~phone', publishesScreen: true)]);

    expect(result.sharesScreen('carol'), isTrue);
  });

  // Sharing from the desktop while in the call from a phone as well: still one
  // person, and their row says they are sharing wherever it is drawn.
  test('a share from one of their devices counts for the person', () {
    final result = presence([
      const P('alice~phone'),
      const P('alice~desktop'),
      const P('alice~desktop_soundshare'),
    ]);

    expect(result.sharesSound('alice'), isTrue);
  });

  test('somebody sharing nothing is sharing nothing', () {
    final result = presence([const P('dave~dev1')]);

    expect(result.sharesScreen('dave'), isFalse);
    expect(result.sharesSound('dave'), isFalse);
    expect(SharePresence.empty.sharesScreen('dave'), isFalse);
  });
}
