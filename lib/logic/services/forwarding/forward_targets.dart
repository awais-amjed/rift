import '../../../data/classes/dm_conversation.dart';
import '../../../data/classes/server.dart';
import '../../../data/enums/channel_type.dart';
import 'forward_target.dart';

/// Everywhere a message can be sent, gathered from what the app already has
/// loaded.
///
/// Pure, so the ordering and the exclusions are the same everywhere and can
/// be checked without a widget. It gathers rather than fetches: a
/// destination list that went to the network would make opening the picker
/// slower than the send it precedes.
abstract final class ForwardTargets {
  /// [currentChannelId] and [currentPeerId] name the conversation the message
  /// is being forwarded *from*. It is left out, because "forward this to
  /// where it already is" is never the intent and offering it is how a
  /// mis-click duplicates a message in place.
  static List<ForwardTarget> gather({
    required List<Server> servers,
    List<DmConversation> serverDms = const [],
    Server? serverDmHost,
    List<DmConversation> centralDms = const [],
    String? currentChannelId,
    String? currentPeerId,
  }) {
    return [
      for (final server in servers)
        for (final channel in server.channels)
          // Voice channels have no message list to forward into, and a
          // channel this member cannot see is not in `server.channels` to
          // begin with — the server filters it (`channel_eligible`).
          if (channel.channelType == ChannelType.text &&
              channel.id != currentChannelId)
            ChannelTarget(server: server, channel: channel),

      if (serverDmHost != null)
        for (final conversation in serverDms)
          if (conversation.peerId != currentPeerId)
            ServerDmTarget(
              server: serverDmHost,
              peerId: conversation.peerId,
              peerName: conversation.peerName,
              peerChatPublicKey: conversation.peerChatPublicKey,
            ),

      for (final conversation in centralDms)
        if (conversation.peerId != currentPeerId)
          CentralDmTarget(
            peerId: conversation.peerId,
            peerHandle: conversation.peerName,
            peerChatPublicKey: conversation.peerChatPublicKey,
          ),
    ];
  }
}
