part of 'channel_presence_cubit.dart';

/// Noticing who left our call without saying so.
///
/// A bot on an SDK from before bots announced their moves is drawn from
/// roster reads alone, and leaving changed nothing a member had read — it
/// stayed in the channel, online and silent, until the app restarted. Only
/// members in the call see it go, so they are the ones who read the roster
/// again.
mixin _RoomPeopleMixin on Cubit<ChannelPresenceState> {
  LiveKitCubit get _livekitCubit;
  VoiceBroadcast? get _voice;

  /// The people in our call last time LiveKit said, as user ids, and the
  /// channel that was.
  Set<String> _roomPeople = const {};
  String? _roomPeopleChannel;

  /// Somebody left our call: if they never said so, read the roster again.
  void _onRoomPeople() {
    final lk = _livekitCubit.state;
    final channel = lk.connectionState == LiveKitConnectionState.connected
        ? lk.currentChannelId
        : null;
    final people = channel == null
        ? const <String>{}
        : {
            for (final participant in lk.participants)
              if (participant is RemoteParticipant &&
                  !ParticipantIdentity.isShare(participant.identity))
                ParticipantIdentity.userIdOf(participant.identity),
          };
    final voice = _voice;
    if (voice != null &&
        channel != null &&
        channel == _roomPeopleChannel &&
        VoiceLocations.leftSilently(
          before: _roomPeople,
          after: people,
          locations: voice.locations,
          channelId: channel,
        ).isNotEmpty) {
      voice.recheckSoon();
    }
    _roomPeople = people;
    _roomPeopleChannel = channel;
  }
}
