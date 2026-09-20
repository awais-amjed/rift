part of 'channel_chat_cubit.dart';

enum ChannelChatStatus {
  /// No text channel open.
  closed,

  /// Keyring/history loading after open.
  loading,

  /// Chat is usable.
  ready,

  /// No key yet, but one has just been asked for and is expected.
  ///
  /// Drawn as loading, not as a problem. Somebody opening a channel for the
  /// first time has no keyring entry until another member's client wraps one
  /// for them, and the doorbell that asks for it is usually answered in well
  /// under a second — so declaring "waiting for channel access" immediately
  /// put a full-screen key warning in front of every new member for exactly
  /// as long as the healing took, and then took it away again. On a fast local
  /// server that is a flash; on a real one it is long enough to read and worry
  /// about.
  ///
  /// Becomes [waitingForKey] if no key arrives within the grace period, which
  /// is the point at which "shortly" stops being an honest thing to imply.
  healingKey,

  /// The keyring has no entry sealed to us yet **and there is nothing here we
  /// can read either** — waiting for another member's client to heal us (they
  /// wrap the channel key on their next channel open).
  ///
  /// Reached only after [healingKey] has given the heal time to happen.
  waitingForKey,

  /// No key, but the channel still has something worth showing: unencrypted
  /// messages we can read, locked rows for the ones we cannot, or both.
  ///
  /// Distinct from [waitingForKey] because that state used to swallow this one.
  /// A member with no key saw a full-screen "waiting" panel over a channel that
  /// might contain build alerts they could read perfectly well, and always
  /// contained a history whose *size* was worth knowing. Reading is the only
  /// thing missing here — sending still needs a key, so the composer stays
  /// away.
  readOnly,

  error,
}

class ChannelChatState {
  final ChannelChatStatus status;

  /// The open text channel, or null when closed.
  final String? channelId;

  /// Decrypted, verified messages — oldest → newest. Pending (optimistic)
  /// sends sit at the end until the server acknowledges them.
  final List<ChatMessage> messages;

  /// Whether older history exists beyond the first loaded page.
  final bool hasMoreHistory;
  final bool isLoadingMore;

  /// Whether newer messages exist past the last loaded one.
  ///
  /// False almost always: the list is the live tail of the conversation and
  /// there is nothing after it. It goes true when a jump lands the reader in
  /// a **window** of history — see the cubit's `showAround`. That window is
  /// deliberately not the present, so three things change with it: scrolling
  /// down loads forward instead of stopping, live messages stop being
  /// appended (they belong after a stretch that is not loaded, and putting
  /// them at the end would draw a gap as if it were not there), and the view
  /// offers a way back.
  final bool hasNewerHistory;

  /// Display names of the bots holding a key to the open channel.
  ///
  /// In cubit state rather than fetched by the header, because it has to be
  /// there the moment the channel is: a marker that appears a beat after the
  /// messages is one people scroll past (BOTS.md §6, rule 4).
  final List<String> botListeners;

  /// The bots a `/` command in this channel can reach.
  ///
  /// In cubit state and loaded before the composer exists, for the same reason
  /// as [botListeners]: a `/` menu that offers a bot which cannot read the
  /// channel is one that offers it exactly when somebody is typing fastest.
  ///
  /// Usually none of them in a private channel: a bot gets in through a role
  /// with `channel_role_access` and no other way, so without one its
  /// `messages_select` never returns the command. An empty list is what turns
  /// `/` handling off entirely, which is the honest state — a slash that
  /// reaches no bot is just a slash.
  final List<ServerMember> bots;

  /// Username → display name for the `@names` these messages contain.
  ///
  /// Only the names actually written, and only those a message here can reach
  /// — `members_by_usernames` is asked with this channel, so a name belonging
  /// to somebody outside a private channel resolves to nothing and is drawn as
  /// the plain text it is. That is the same set `validate_message_mentions`
  /// keeps, so what lights up is what was delivered.
  ///
  /// It replaces a map built from the whole roster, which could only ever be as
  /// complete as the roster was — and past a thousand members it was not.
  final Map<String, String> mentionNames;

  /// Members currently typing in the open channel, by user id → display name
  /// (excludes us). Backed by short-lived expiry timers in the cubit.
  final Map<String, String> typingUsers;

  /// Why the channel would not open, when [status] is
  /// [ChannelChatStatus.error].
  final ChatFailure? failure;

  const ChannelChatState({
    this.status = ChannelChatStatus.closed,
    this.channelId,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.hasNewerHistory = false,
    this.typingUsers = const {},
    this.botListeners = const [],
    this.bots = const [],
    this.mentionNames = const {},
    this.failure,
  });

  ChannelChatState copyWith({
    ChannelChatStatus? status,
    String? channelId,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    bool? hasNewerHistory,
    Map<String, String>? typingUsers,
    List<String>? botListeners,
    List<ServerMember>? bots,
    Map<String, String>? mentionNames,
    ChatFailure? failure,
    bool clearFailure = false,
  }) {
    return ChannelChatState(
      status: status ?? this.status,
      channelId: channelId ?? this.channelId,
      messages: messages ?? this.messages,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasNewerHistory: hasNewerHistory ?? this.hasNewerHistory,
      typingUsers: typingUsers ?? this.typingUsers,
      botListeners: botListeners ?? this.botListeners,
      // No clear flags: `openChannel` builds a fresh state, so a channel opened
      // after another starts empty rather than inheriting its neighbour's bots
      // or the names somebody said in it.
      bots: bots ?? this.bots,
      mentionNames: mentionNames ?? this.mentionNames,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}
