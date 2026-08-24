part of 'channel_chat_cubit.dart';

/// Telling the user about a message in the channel they have open.
///
/// Every other channel is [ServerNotificationsCubit]'s, which sees only
/// ciphertext and can say no more than that something arrived. This one
/// holds the key, so it can name the sender, quote the line, and — the point
/// of the exercise — tell being mentioned from being in the room.
mixin _ChatNotifyMixin on Cubit<ChannelChatState> {
  ServerCubit get _serverCubit;

  /// Raise notifications for messages that arrived in the channel on screen.
  ///
  /// Every other channel is `ServerNotificationsCubit`'s, which sees only
  /// ciphertext and can say no more than "new message in #general". This one
  /// holds the key, so it can name the sender, quote the line, and — the point
  /// of the exercise — tell being mentioned from being in the room. The two
  /// divide by who can read the message so that exactly one of them speaks.
  ///
  /// Unfocused only, same as everywhere else: a notification for something you
  /// are looking at is noise.
  void _notify(List<ChatMessage> incoming) {
    if (incoming.isEmpty || WindowFocusService.instance.isFocused) return;

    final server = _serverCubit.state.selectedServer;
    final me = server?.user?.username.toLowerCase();
    final channelName = _openChannelName(server);
    final mentionable = me == null ? const <String>{} : {me};

    for (final message in incoming) {
      // The wording is [ChatNotice]'s rather than this file's, because the
      // push isolate says the same sentence about the same message and the two
      // must not drift apart.
      final notice = ChatNotice.channel(
        author: message.authorName,
        channel: channelName,
        text: message.text,
        mentionable: mentionable,
      );
      NotificationService.instance.showMessage(
        title: notice.title,
        body: notice.body,
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
