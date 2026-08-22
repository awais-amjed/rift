import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/voice_tiles.dart';

/// A stand-in participant. The rule under test only needs two facts about
/// one, which is the point of it being generic.
class P {
  final String identity;
  final bool sharing;

  const P(this.identity, {this.sharing = false});
}

List<VoiceTile<P>> tiles(List<P> participants) => voiceTilesFor(
  participants,
  hasScreenshareIdentity: (p) => p.identity.endsWith('_screenshare'),
  publishesScreenshare: (p) => p.sharing,
);

/// A screen reaches the room by two different routes and only one of them
/// arrives as its own participant. The grid used to assume the other did not
/// exist, so a screen shared from a phone was drawn by nobody — not even the
/// phone that was sharing it.
void main() {
  test('an ordinary participant is one cell', () {
    final result = tiles([const P('alice~dev1')]);

    expect(result, hasLength(1));
    expect(result.single.isScreenshare, isFalse);
  });

  test("a desktop's separate share connection is one screenshare cell", () {
    // It carries no camera and no microphone; it exists only for the screen.
    final result = tiles([const P('alice~dev1_screenshare')]);

    expect(result, hasLength(1));
    expect(result.single.isScreenshare, isTrue);
  });

  test('a phone sharing gets a cell for itself and one for its screen', () {
    // The bug: one participant, two things to draw. Reading the identity
    // suffix found no share, and the single cell then looked for a camera.
    final result = tiles([const P('bob~phone', sharing: true)]);

    expect(result, hasLength(2));
    expect(result[0].isScreenshare, isFalse);
    expect(result[1].isScreenshare, isTrue);
    expect(result[1].participant.identity, 'bob~phone');
  });

  test("a share sits beside its owner, not at the end of the grid", () {
    final result = tiles([
      const P('alice~dev1'),
      const P('bob~phone', sharing: true),
      const P('carol~dev2'),
    ]);

    expect(
      result.map(
        (t) => '${t.participant.identity}${t.isScreenshare ? '#s' : ''}',
      ),
      ['alice~dev1', 'bob~phone', 'bob~phone#s', 'carol~dev2'],
    );
  });

  test('both routes can be in the room at once', () {
    // A desktop and a phone sharing simultaneously: three people, two screens,
    // five cells.
    final result = tiles([
      const P('alice~dev1'),
      const P('alice~dev1_screenshare'),
      const P('bob~phone', sharing: true),
      const P('carol~dev2'),
    ]);

    expect(result, hasLength(5));
    expect(result.where((t) => t.isScreenshare), hasLength(2));
  });

  test('a dedicated share connection is never doubled', () {
    // Its publication *is* a screenshare track, so a naive rule would give it
    // a camera cell as well and draw an avatar next to the screen.
    final result = tiles([const P('alice~dev1_screenshare', sharing: true)]);

    expect(result, hasLength(1));
    expect(result.single.isScreenshare, isTrue);
  });

  test('nobody in the room is no cells', () {
    expect(tiles([]), isEmpty);
  });
}
