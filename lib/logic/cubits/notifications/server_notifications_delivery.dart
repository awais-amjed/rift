part of 'server_notifications_cubit.dart';

/// What a message arriving on any server does here: a badge, and a chime or
/// an OS notification when nobody else will raise one.
mixin _DeliveryMixin
    on
        Cubit<NotificationsState>,
        _PeerNamesMixin,
        _SubscriptionsMixin,
        _ReadMarkingMixin,
        _LevelsMixin {
  DmCubit get _dmCubit;

  /// The open channel and conversation, and whether their surface shows.
  String? get _openServerId;
  String? get _openChannelId;
  String? get _openDmServerId;
  String? get _openPeerId;
  bool get _channelOnScreen;
  bool get _dmOnScreen;

  Server? _serverById(String serverId);

  /// A message landed in a channel on this server. Realtime only delivers rows
  /// this member could have selected, so arriving here already means "you can
  /// see this".
  @override
  void _onChannelMessage(String serverId, Map<String, dynamic> row) {
    if (isClosed) return;
    final channelId = row['channel_id'] as String?;
    if (channelId == null) return;
    // Our own messages come back over the same subscription.
    if (row['sender_id'] == _subs[serverId]?.userId) return;

    final focused = WindowFocusService.instance.isFocused;
    final isOpenChannel =
        _channelOnScreen &&
        serverId == _openServerId &&
        channelId == _openChannelId;

    // Looking at this exact channel → it's read; don't badge or notify.
    if (focused && isOpenChannel) {
      markChannelRead(serverId, channelId);
      return;
    }

    emit(state.incremented(serverId, channelId));

    // The open channel's notification belongs to ChannelChatCubit, which holds
    // that channel's key. This row is ciphertext, so the best it could say is
    // "new message"; that one can name the sender, quote the message, and tell
    // a mention from an ordinary line. Whoever can read it should be the one
    // describing it — and only one of us may, or it arrives twice.
    final level = state.channelLevel(serverId, channelId);
    if (!level.announces(mentioned: _rowNamesMe(serverId, row))) return;

    // Looking at the app but not at this channel: no notification, which
    // would be a banner over the window you are using, but the chime. An
    // unfocused window gets it from [NotificationService] instead.
    if (focused) {
      unawaited(SoundService.instance.play(AppSound.message));
      return;
    }
    if (!isOpenChannel) {
      final server = _serverById(serverId);
      String? channelName;
      for (final c in server?.channels ?? const []) {
        if (c.id == channelId) {
          channelName = c.name;
          break;
        }
      }
      NotificationService.instance.showMessage(
        title: server?.name ?? 'Rift',
        body: channelName != null
            ? 'New message in #$channelName'
            : 'New message',
        payload: ConversationNotificationPayload.channel(
          serverId,
          channelId,
        ).encode(),
      );
    }
  }

  /// Badge an incoming DM, and notify for it if no one else will.
  ///
  /// [DmCubit] raises the notification for the server it lists — the
  /// selected one — off the conversation list, where it holds the keys and
  /// can quote the message. It is connected to one server at a time, though,
  /// so a DM arriving on any other server used to badge in silence — the one place a message can
  /// arrive with nobody able to speak for it.
  ///
  /// This covers exactly that gap. The row is ciphertext, so it names the
  /// sender and stops there rather than inventing a preview. The split is by
  /// server, not by surface, so precisely one of the two speaks for any DM.
  @override
  void _onDmMessage(String serverId, Map<String, dynamic> row) {
    if (isClosed) return;
    final peerId = row['sender_id'] as String?;
    if (peerId == null) return;

    if (WindowFocusService.instance.isFocused &&
        _dmOnScreen &&
        serverId == _openDmServerId &&
        peerId == _openPeerId) {
      markDmRead(serverId, peerId);
      return;
    }
    emit(state.incrementedDm(serverId, peerId));

    // A DM has nobody else in it to be named among, so `mentions` reads as
    // `all` here — the same answer the server's ring trigger gives it.
    if (state.dmLevel(serverId, peerId).isMuted) return;

    // Focused, on any server: the chime, as for a channel. DmCubit never
    // speaks while the window is focused, so this is the only one that does.
    if (WindowFocusService.instance.isFocused) {
      unawaited(SoundService.instance.play(AppSound.message));
      return;
    }
    if (serverId != _dmCubit.serverId) {
      unawaited(_notifyBackgroundDm(serverId, peerId));
    }
  }

  /// A message in a channel was edited or deleted.
  ///
  /// The badge counted it when it arrived, so a delete before it was read has
  /// to take it back off. The payload names the message and not whether it
  /// still exists, so the count is asked for again rather than adjusted here
  /// — and only while this channel has something unread, which leaves an
  /// edit anywhere else costing nothing.
  @override
  void _onChannelMessageChanged(String serverId, Map<String, dynamic> row) {
    if (isClosed) return;
    final channelId = row['channel_id'] as String?;
    if (channelId == null) return;
    if (state.unreadForChannel(serverId, channelId) == 0) return;
    unawaited(_seed(serverId));
  }

  /// A DM to us was edited or deleted. The same as a channel's, except that
  /// the payload names only the message, so any unread DM on the server is
  /// reason enough to count again.
  @override
  void _onDmMessageChanged(String serverId) {
    if (isClosed) return;
    if (state.dmUnreadByServer[serverId]?.isEmpty ?? true) return;
    unawaited(_seed(serverId));
  }

  /// Announce a DM from a server the user isn't currently on.
  ///
  /// Re-checks focus after the name lookup: the user may well have come back to
  /// the window while it was in flight, and a notification for a window being
  /// looked at is the noise this whole tier exists to avoid.
  Future<void> _notifyBackgroundDm(String serverId, String peerId) async {
    final name = await _peerDisplayName(serverId, peerId);
    if (isClosed || WindowFocusService.instance.isFocused) return;
    await NotificationService.instance.showMessage(
      title: _serverById(serverId)?.name ?? 'Rift',
      body: name != null ? '$name sent you a message' : 'New direct message',
      payload: ConversationNotificationPayload.serverDm(
        serverId,
        peerId,
      ).encode(),
    );
  }
}
