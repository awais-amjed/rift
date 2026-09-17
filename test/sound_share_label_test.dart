import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/sound_share_label.dart';

/// "RotB's sound" named the one part nobody needed naming. A room listening to
/// music wants to know what is playing; whose it is only matters when two
/// people are sharing at once.
void main() {
  test('names the application, and who has it on', () {
    expect(
      soundShareLabel(owner: 'RotB', app: 'Spotify', isOwn: false),
      'RotB · Spotify',
    );
  });

  test('your own share says so rather than repeating your name', () {
    expect(
      soundShareLabel(owner: 'RotaRota', app: 'Spotify', isOwn: true),
      'You · Spotify',
    );
  });

  // An application that named itself nothing, or a share from a client that
  // predates the label: the tile still has to say whose it is, because a room
  // with two shares in it needs to know which one to turn down.
  test('falls back to the owner when the application gave no name', () {
    expect(
      soundShareLabel(owner: 'RotB', app: null, isOwn: false),
      'RotB’s audio',
    );
    expect(
      soundShareLabel(owner: 'RotB', app: '   ', isOwn: false),
      'RotB’s audio',
    );
    expect(
      soundShareLabel(owner: 'RotaRota', app: '', isOwn: true),
      'Your audio',
    );
  });

  test('an unnamed owner leaves the application standing alone', () {
    expect(soundShareLabel(owner: '', app: 'Spotify', isOwn: false), 'Spotify');
  });
}
