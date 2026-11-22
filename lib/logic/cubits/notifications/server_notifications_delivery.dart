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
  ChannelChatCubit get _chatCubit;

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

    // Named on the row's word, like the ring: the badge it adds is put right
    // by the next count if the word was false.
    final mentioned = _rowNamesMe(serverId, row);
    emit(state.incremented(serverId, channelId, mentioned: mentioned));

    // The open channel's notification belongs to ChannelChatCubit, which holds
    // that channel's key. This row is ciphertext, so the best it could say is
    // "new message"; that one can name the sender, quote the message, and tell
    // a mention from an ordinary line. Whoever can read it should be the one
    // describing it — and only one of us may, or it arrives twice.
    final level = state.channelLevel(serverId, channelId);
    if (!level.announces(mentioned: mentioned)) return;

    unawaited(_speakForChannelMessage(serverId, channelId, row, level));
  }

  /// Chime, say or notify for a channel message the badge already counted —
  /// once the database confirms it.
  ///
  /// The ring's payload is anybody's to write: any member may broadcast on
  /// the server's topic, a timed-out one included. Taken at its word, one
  /// broadcast naming the admin and `mentions_all` chimed in every window
  /// and put "New message in #general" over every unfocused one, about a
  /// message that never existed (review, Nov 23). The badge it added is put
  /// right by the next count; what was said out loud could not be taken back.
  Future<void> _speakForChannelMessage(
    String serverId,
    String channelId,
    Map<String, dynamic> ring,
    NotificationLevel level,
  ) async {
    final real = await _announcedRow(serverId, ring, dm: false);
    if (real == null ||
        real['channel_id'] != channelId ||
        real['sender_id'] != ring['sender_id'] ||
        isClosed) {
      return;
    }
    final named = _rowNamesMe(serverId, real);
    if (!level.announces(mentioned: named)) return;

    // It rang, so it is likely to be opened next, from the notification or
    // the badge: read it into the channel's saved copy now, so that opening
    // it shows this message at once rather than a ping after the click.
    _chatCubit.refreshSavedCopy(serverId, channelId);

    // Looking at the app but not at this channel: no notification, which
    // would be a banner over the window you are using, but the chime. An
    // unfocused window gets it from [NotificationService] instead.
    if (WindowFocusService.instance.isFocused) {
      // Opened while the row was being asked for: it is read, not news.
      if (_channelOnScreen &&
          serverId == _openServerId &&
          channelId == _openChannelId) {
        return;
      }
      unawaited(SoundService.instance.play(AppSound.message));
      // A mention says where it is, too: the chime alone sent the person
      // looking through the badges for it.
      if (named) unawaited(_sayMentionInApp(serverId, channelId, real));
      return;
    }
    // Loaded is what counts here, not on screen: ChannelChatCubit speaks for
    // its channel behind a DM surface too, and asking about the surface
    // announced a mention there twice, with two chimes.
    final chatSpeaks = serverId == _openServerId && channelId == _openChannelId;
    if (!chatSpeaks) {
      final server = _serverById(serverId);
      final channelName = _channelName(server, channelId);
      await NotificationService.instance.showMessage(
        title: server?.name ?? 'Rift',
        body: channelName != null
            ? 'New message in #$channelName'
            : 'New message',
        target: ConversationNotificationPayload.channel(serverId, channelId),
        messageId: real['id'] as int?,
      );
    }
  }

  /// The row a `message` or `dm` ring names, as the database has it; null
  /// when it does not exist, cannot be seen, or could not be asked about.
  Future<Map<String, dynamic>?> _announcedRow(
    String serverId,
    Map<String, dynamic> ring, {
    required bool dm,
  }) async {
    final id = ring['id'];
    if (id is! int || !_subs.containsKey(serverId)) return null;
    final answer = await UnreadApi(
      _session.on(serverId),
    ).announcedRow(dm: dm, messageId: id);
    if (!answer.success) return null;
    final data = answer.data;
    final row = data is Map<String, dynamic> ? data['message'] : null;
    return row is Map<String, dynamic> ? row : null;
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
    unawaited(_speakForDm(serverId, peerId, row));
  }

  /// The DM half of [_speakForChannelMessage]: a co-member may broadcast on
  /// this member's own topic, so "Anyone sent you a message" was theirs to
  /// say until the row was asked for.
  Future<void> _speakForDm(
    String serverId,
    String peerId,
    Map<String, dynamic> ring,
  ) async {
    final focused = WindowFocusService.instance.isFocused;
    // Unfocused on the listed server, DmCubit speaks from its list, which is
    // read from the database already.
    if (!focused && serverId == _dmCubit.serverId) {
      _dmCubit.refreshSavedCopy(serverId, peerId);
      return;
    }
    final real = await _announcedRow(serverId, ring, dm: true);
    if (real == null ||
        real['sender_id'] != peerId ||
        real['recipient_id'] != _subs[serverId]?.userId ||
        isClosed) {
      return;
    }
    // As for a channel: opened next, it shows this message at once.
    _dmCubit.refreshSavedCopy(serverId, peerId);

    // Focused, on any server: the chime, and who it is from, inside the app.
    // DmCubit never speaks while the window is focused, so this is the only
    // one that does.
    if (WindowFocusService.instance.isFocused) {
      if (_dmOnScreen && serverId == _openDmServerId && peerId == _openPeerId) {
        return;
      }
      unawaited(SoundService.instance.play(AppSound.message));
      unawaited(_sayDmInApp(serverId, peerId));
      return;
    }
    if (serverId != _dmCubit.serverId) {
      await _notifyBackgroundDm(serverId, peerId, real['id'] as int?);
    }
  }

  String? _channelName(Server? server, String channelId) {
    for (final c in server?.channels ?? const []) {
      if (c.id == channelId) return c.name;
    }
    return null;
  }

  /// Say inside the focused window that somebody wrote in [channelId] and,
  /// by the row's say-so, named us. The row is ciphertext, so who and where
  /// is all there is to say — and "mentioned you" would be the sender's word
  /// for it, which [_rowNamesMe] is never allowed to put into a sentence.
  Future<void> _sayMentionInApp(
    String serverId,
    String channelId,
    Map<String, dynamic> row,
  ) async {
    final senderId = row['sender_id'] as String?;
    final name = senderId == null
        ? null
        : await _peerDisplayName(serverId, senderId);
    if (isClosed) return;
    final server = _serverById(serverId);
    final channelName = _channelName(server, channelId);
    NotificationService.instance.showInApp(
      senderId: senderId,
      sender: name ?? 'Somebody',
      avatarPath: _avatarOf(serverId, senderId),
      what: channelName == null
          ? 'sent a message'
          : 'sent a message in #$channelName',
      place: server?.name,
      target: ConversationNotificationPayload.channel(serverId, channelId),
    );
  }

  /// Say inside the focused window that a DM arrived.
  Future<void> _sayDmInApp(String serverId, String peerId) async {
    final name = await _peerDisplayName(serverId, peerId);
    if (isClosed) return;
    NotificationService.instance.showInApp(
      senderId: peerId,
      sender: name ?? 'Somebody',
      avatarPath: _avatarOf(serverId, peerId),
      what: 'sent you a message',
      place: _serverById(serverId)?.name,
      target: ConversationNotificationPayload.serverDm(serverId, peerId),
    );
  }

  /// The picture of somebody [_peerDisplayName] has just looked up.
  String? _avatarOf(String serverId, String? userId) => userId == null
      ? null
      : _session.members.lookup(serverId, userId)?.avatarPath;

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
  Future<void> _notifyBackgroundDm(
    String serverId,
    String peerId,
    int? messageId,
  ) async {
    final name = await _peerDisplayName(serverId, peerId);
    if (isClosed || WindowFocusService.instance.isFocused) return;
    await NotificationService.instance.showMessage(
      title: _serverById(serverId)?.name ?? 'Rift',
      body: name != null ? '$name sent you a message' : 'New direct message',
      target: ConversationNotificationPayload.serverDm(serverId, peerId),
      messageId: messageId,
    );
  }
}
