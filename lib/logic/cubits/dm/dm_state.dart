part of 'dm_cubit.dart';

enum DmChatStatus { closed, loading, ready, error }

class DmState {
  /// Conversations on the selected server, newest activity first.
  final List<DmConversation> conversations;
  final bool conversationsLoading;

  /// Whether another page of conversations follows — proved by the spare row
  /// `dm_conversations` over-fetched (`011_directory.sql`), never inferred from a
  /// page being full.
  final bool hasMoreConversations;

  /// The open conversation's peer, or null when none is open.
  final String? openPeerId;
  final String? openPeerName;

  final DmChatStatus chatStatus;

  /// Decrypted, verified messages of the open conversation — oldest →
  /// newest; pending optimistic sends at the end.
  final List<ChatMessage> messages;
  final bool hasMoreHistory;
  final bool isLoadingMore;

  /// The open peer's display name while they're typing, else null.
  final String? typingPeerName;

  final String? error;

  const DmState({
    this.conversations = const [],
    this.conversationsLoading = false,
    this.hasMoreConversations = false,
    this.openPeerId,
    this.openPeerName,
    this.chatStatus = DmChatStatus.closed,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.typingPeerName,
    this.error,
  });

  DmState copyWith({
    List<DmConversation>? conversations,
    bool? conversationsLoading,
    bool? hasMoreConversations,
    String? openPeerId,
    String? openPeerName,
    DmChatStatus? chatStatus,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    String? typingPeerName,
    bool clearTyping = false,
    String? error,
    bool clearError = false,
    bool closeConversation = false,
  }) {
    return DmState(
      conversations: conversations ?? this.conversations,
      conversationsLoading: conversationsLoading ?? this.conversationsLoading,
      hasMoreConversations: hasMoreConversations ?? this.hasMoreConversations,
      openPeerId: closeConversation ? null : (openPeerId ?? this.openPeerId),
      openPeerName: closeConversation
          ? null
          : (openPeerName ?? this.openPeerName),
      chatStatus: closeConversation
          ? DmChatStatus.closed
          : (chatStatus ?? this.chatStatus),
      messages: closeConversation ? const [] : (messages ?? this.messages),
      hasMoreHistory: closeConversation
          ? false
          : (hasMoreHistory ?? this.hasMoreHistory),
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      typingPeerName: (closeConversation || clearTyping)
          ? null
          : (typingPeerName ?? this.typingPeerName),
      error: clearError ? null : (error ?? this.error),
    );
  }
}
