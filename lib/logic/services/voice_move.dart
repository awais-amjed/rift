import '../../data/classes/channel.dart';
import '../../data/enums/channel_type.dart';

/// Where a member can be pulled to.
///
/// Pure, because "which channels does the Move to submenu list" is a rule, not
/// a widget: it decides what staff are offered, and offering the channel
/// someone is already in is the one thing that can't do anything.
class VoiceMove {
  VoiceMove._();

  /// The voice channels [from] can be moved into — every voice channel on the
  /// server except the one they're in. Text channels have no call to join.
  ///
  /// Order is left as the server's, which is the order the sidebar shows: the
  /// submenu should read like the channel list it is pointing at.
  static List<Channel> destinations(
    Iterable<Channel> channels, {
    String? from,
  }) => [
    for (final channel in channels)
      if (channel.channelType == ChannelType.voice && channel.id != from)
        channel,
  ];
}
