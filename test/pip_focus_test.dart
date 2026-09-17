import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/pip_focus.dart';
import 'package:rift/logic/services/voice_tiles.dart';

/// A stand-in participant, carrying only what the ranking reads.
class P {
  final String name;
  final bool local;
  final bool speaking;

  const P(this.name, {this.local = false, this.speaking = false});
}

VoiceTile<P> cell(P p, {bool screen = false}) => VoiceTile(
  participant: p,
  kind: screen ? VoiceTileKind.screenshare : VoiceTileKind.person,
);

/// One rectangle, several candidates. What goes in it is the thing you left
/// the app still wanting to see.
VoiceTile<P>? focus(List<VoiceTile<P>> tiles, {Set<VoiceTile<P>>? without}) =>
    pipFocus(
      tiles,
      isLocal: (p) => p.local,
      isSpeaking: (p) => p.speaking,
      hasVideo: (t) => !(without?.contains(t) ?? false),
    );

void main() {
  test('a shared screen wins', () {
    final screen = cell(const P('alice'), screen: true);
    final talker = cell(const P('bob', speaking: true));

    expect(focus([talker, screen]), screen);
  });

  test('otherwise whoever is talking', () {
    final quiet = cell(const P('alice'));
    final talker = cell(const P('bob', speaking: true));

    expect(focus([quiet, talker]), talker);
  });

  test('otherwise anyone with a camera on', () {
    final quiet = cell(const P('alice'));

    expect(focus([quiet]), quiet);
  });

  test('your own camera is a mirror, not a reason to float', () {
    expect(focus([cell(const P('me', local: true, speaking: true))]), isNull);
  });

  test('your own shared screen would be drawing itself', () {
    expect(
      focus([cell(const P('me', local: true), screen: true)]),
      isNull,
      reason: 'the window would be showing the window',
    );
  });

  test('a cell with nothing to render is not a candidate', () {
    // An avatar shrunk to a thumbnail is a coloured square.
    final avatarOnly = cell(const P('alice', speaking: true));
    final withCamera = cell(const P('bob'));

    expect(focus([avatarOnly, withCamera], without: {avatarOnly}), withCamera);
  });

  test('an audio call floats nothing at all', () {
    // Not a black rectangle over whatever you went to do — the notification
    // is the right surface for a call with nothing to see.
    final voices = [cell(const P('alice')), cell(const P('bob'))];

    expect(focus(voices, without: voices.toSet()), isNull);
  });

  test('an empty room is nothing to float', () {
    expect(focus([]), isNull);
  });

  test('the first screen wins when two people share', () {
    final first = cell(const P('alice'), screen: true);
    final second = cell(const P('bob'), screen: true);

    expect(focus([first, second]), first);
  });
}
