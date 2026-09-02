part of 'channel_chat_cubit.dart';

enum ChannelChatStatus {
  /// No text channel open.
  closed,

  /// Keyring/history loading after open.
  loading,

  /// Chat is usable.
  ready,

  /// The keyring has no entry sealed to us yet **and there is nothing here we
  /// can read either** — waiting for another member's client to heal us (they
  /// wrap the channel key on their next channel open).
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

  /// Display names of the bots holding a key to the open channel.
  ///
  /// In cubit state rather than fetched by the header, because it has to be
  /// there the moment the channel is: a marker that appears a beat after the
  /// messages is one people scroll past (BOTS.md §6, rule 4).
  final List<String> botListeners;

  /// Server members a message here can reach, or null when that is everybody.
  ///
  /// Only a private channel has one. In cubit state and loaded before the
  /// composer exists, for the same reason as [botListeners]: an `@` menu that
  /// offers the whole server for the first beat of a private channel is one
  /// that offers outsiders exactly when somebody is typing fastest.
  final Set<String>? audience;

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
    this.typingUsers = const {},
    this.botListeners = const [],
    this.audience,
    this.failure,
  });

  ChannelChatState copyWith({
    ChannelChatStatus? status,
    String? channelId,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    Map<String, String>? typingUsers,
    List<String>? botListeners,
    Set<String>? audience,
    ChatFailure? failure,
    bool clearFailure = false,
  }) {
    return ChannelChatState(
      status: status ?? this.status,
      channelId: channelId ?? this.channelId,
      messages: messages ?? this.messages,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      typingUsers: typingUsers ?? this.typingUsers,
      botListeners: botListeners ?? this.botListeners,
      // No clear flag: `openChannel` builds a fresh state, so a public channel
      // opened after a private one starts null rather than inheriting a list.
      audience: audience ?? this.audience,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}
