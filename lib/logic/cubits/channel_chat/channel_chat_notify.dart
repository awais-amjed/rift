part of 'channel_chat_cubit.dart';

/// Telling the user about a message in the channel they have open.
///
/// Every other channel is [ServerNotificationsCubit]'s, which sees only
/// ciphertext and can say no more than that something arrived. This one
/// holds the key, so it can name the sender, quote the line, and — the point
/// of the exercise — tell being mentioned from being in the room.
mixin _ChatNotifyMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;
  NotificationLevel Function(String channelId)? get _notificationLevelFor;

  /// Raise notifications for messages that arrived in the channel on screen.
  ///
  /// Every other channel is `ServerNotificationsCubit`'s, which sees only
  /// ciphertext and can say no more than "new message in #general". This one
  /// holds the key, so it can name the sender, quote the line, and — the point
  /// of the exercise — tell being mentioned from being in the room. The two
  /// divide by who can read the message so that exactly one of them speaks.
  ///
  /// Being the side that can read it is also what makes this the honest place
  /// to apply [NotificationLevel.mentions]. Everywhere else has to take the
  /// sender's word for who was named; here the answer comes out of the
  /// plaintext, so a message that claimed a mention it did not make gets
  /// nothing.
  ///
  /// Unfocused only, same as everywhere else: a notification for something you
  /// are looking at is noise.
  void _notify(List<ChatMessage> incoming) {
    if (incoming.isEmpty || WindowFocusService.instance.isFocused) return;

    final channelId = state.channelId;
    if (channelId == null) return;
    final level =
        _notificationLevelFor?.call(channelId) ??
        NotificationLevel.channelDefault;
    if (level == NotificationLevel.none) return;

    final server = _serverCubit.state.selectedServer;
    final channelName = _openChannelName(server);
    final mentionable = Mentions.mentionableFor(server?.user?.username);

    for (final message in incoming) {
      // The wording is [ChatNotice]'s rather than this file's, because the
      // push isolate says the same sentence about the same message and the two
      // must not drift apart. It also answers the question the level turns on,
      // which is why the level is applied to its result rather than beside it.
      final notice = ChatNotice.channel(
        author: message.authorName,
        channel: channelName,
        text: message.text,
        mentionable: mentionable,
      );
      if (!level.announces(mentioned: notice.mentioned)) continue;
      NotificationService.instance.showMessage(
        title: notice.title,
        body: notice.body,
        payload: server == null
            ? null
            : ConversationNotificationPayload.channel(
                server.id,
                channelId,
              ).encode(),
      );
    }
  }

  String _openChannelName(Server? server) {
    for (final c in server?.channels ?? const <Channel>[]) {
      if (c.id == state.channelId) return c.name;
    }
    return 'channel';
  }
}
