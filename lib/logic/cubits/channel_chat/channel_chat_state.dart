part of 'channel_chat_cubit.dart';

enum ChannelChatStatus {
  /// No text channel open.
  closed,

  /// Keyring/history loading after open.
  loading,

  /// Chat is usable.
  ready,

  /// The keyring has no entry sealed to us yet — waiting for another member's
  /// client to heal us (they wrap the channel key on their next channel open).
  waitingForKey,

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
    this.failure,
  });

  ChannelChatState copyWith({
    ChannelChatStatus? status,
    String? channelId,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    Map<String, String>? typingUsers,
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
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}
