import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';

/// A phone's stream had no tile for anyone watching the call until they
/// pressed Watch on the phone's card.
///
/// A phone shares on the connection it talks on, so starting a stream changes
/// a participant already in the room — and LiveKit changes its participants
/// in place. The state emitted for the new track held the same objects as the
/// one before, compared equal, and was dropped as no change. The grid kept the
/// cells it had until watching changed something else in the state.

/// One connection, publishing whatever [publications] holds right now, the
/// way a LiveKit participant does.
class _Connection extends Fake implements Participant {
  _Connection(this.identity);

  @override
  final String identity;

  final List<TrackPublication> publications = [];

  @override
  List<TrackPublication> get videoTrackPublications => publications;
}

class _Publication extends Fake implements TrackPublication {
  _Publication(this.source);

  @override
  final TrackSource source;
}

void main() {
  test('a phone starting a stream is a change to the call', () {
    final phone = _Connection('user-1');
    final before = const LiveKitState().copyWith(participants: [phone]);

    phone.publications.add(_Publication(TrackSource.screenShareVideo));
    final after = before.copyWith(participants: [phone]);

    expect(after, isNot(before));
  });

  test('a camera coming on adds no cell, so it is not one', () {
    // The tile follows its own participant for that. A state that changed on
    // it too would rebuild the whole stage for something one tile draws.
    final phone = _Connection('user-1');
    final before = const LiveKitState().copyWith(participants: [phone]);

    phone.publications.add(_Publication(TrackSource.camera));
    final after = before.copyWith(participants: [phone]);

    expect(after, before);
  });
}
