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

  final String? error;

  const ChannelChatState({
    this.status = ChannelChatStatus.closed,
    this.channelId,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.error,
  });

  ChannelChatState copyWith({
    ChannelChatStatus? status,
    String? channelId,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
  }) {
    return ChannelChatState(
      status: status ?? this.status,
      channelId: channelId ?? this.channelId,
      messages: messages ?? this.messages,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
