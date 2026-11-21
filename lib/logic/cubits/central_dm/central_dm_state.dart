part of 'central_dm_cubit.dart';

/// How far central DMs are from usable on this device.
enum CentralDmStatus {
  /// No central session or locked vault — central DMs unavailable.
  signedOut,

  /// Signed in but no directory profile yet — the user must claim a handle.
  needsHandle,

  ready,
  error,

  /// The account published another vault's keys, and its cloud backup is
  /// not this device's vault: the backup conflict has not been answered, or
  /// was put off. Nothing is published or read until it is.
  otherVault,
}

/// Chat status of the open central conversation (mirrors the server-DM enum
/// but kept separate — the tiers evolve independently).
enum DmChatStatus { closed, loading, ready, error }

/// Central DMs: the conversation list, the open conversation, friends and the
/// daily quota. Handles, not display names, because central has no server to
/// name anybody.
class CentralDmState extends Equatable {
  final CentralDmStatus status;
  final String? myHandle;
  final bool claiming;

  /// Conversations, newest activity first. Peer names are handles.
  final List<DmConversation> conversations;
  final bool conversationsLoading;

  /// Whether another page of conversations exists — proved by the row
  /// `dm_conversations` over-fetched, never inferred from a page being full.
  final bool hasMoreConversations;

  /// peer id → unread messages from them. A zero count is an absent key, so
  /// `unreadByPeer[id] ?? 0` is the only correct way to read it.
  final Map<String, int> unreadByPeer;

  /// peer id → how much that conversation may interrupt. A peer nobody has an
  /// opinion about is absent, and [NotificationLevel.dmDefault] answers for
  /// them — which is what lets the default be changed later without touching
  /// anybody's stored rows.
  final Map<String, NotificationLevel> levelsByPeer;

  /// How many people are in each part of the friends graph, plus the rows of
  /// whichever tabs have been opened.
  ///
  /// What it gates is the whole point of the central tier having a gate at
  /// all: a conversation with somebody you are not friends with is a
  /// *request*, and it is drawn, counted and composed into differently.
  ///
  /// The rows are not loaded until a tab asks for them — see
  /// [FriendBuckets].
  final FriendBuckets friends;

  /// The lists the friends tab on screen draws, so a change to the graph can
  /// refetch the pages somebody is actually looking at. Pending draws two —
  /// requests to you and requests you sent — and keeping only one of them
  /// left the other unloaded after accepting, its spinner turning forever.
  final List<FriendBucket> openBuckets;

  /// Daily-quota meter (null until first fetched).
  final int? quota;
  final int? remaining;

  /// Whether the content pane is showing the friends page.
  ///
  /// Only a phone needs to be told. On a desktop the friends page *is* the
  /// resting state, so "no conversation open" says it — but on a phone the
  /// pane with nothing open is the conversation list itself (`HomeView`), and
  /// without a flag there would be no way to navigate to friends at all.
  final bool friendsOpen;

  final String? openPeerId;
  final String? openPeerHandle;

  /// Where you stand with the open peer, asked of central when the
  /// conversation opens and after every change to the friends graph — see
  /// [stateFor]. Null until the first answer.
  final FriendshipState? openPeerState;

  final DmChatStatus chatStatus;
  final List<ChatMessage> messages;
  final bool hasMoreHistory;
  final bool isLoadingMore;

  /// Whether newer messages exist past the last loaded one.
  ///
  /// True only while a jump has put the reader in a **window** of history
  /// rather than at the live end — see the cubit's `showAround`. While it
  /// is, scrolling down loads forward, arriving messages are not appended
  /// (they belong after a stretch that is not loaded), and the view offers a
  /// way back.
  final bool hasNewerHistory;

  final String? error;

  /// The open conversation's page could not be fetched and nothing was saved
  /// to show instead: [chatStatus] is `error`, and Try again opens it again.
  /// Before, it was `ready` with no messages — it looked empty, cleared its
  /// badge for messages never shown, and the next arrival was read from the
  /// start of the conversation as if it were new.
  final bool loadFailed;

  /// Text to seed the add-friend field with. Set when arriving from a member's
  /// context menu, where their server display name is the best guess at a
  /// handle — central accounts are separate identities, so nothing links the
  /// two and the name is a suggestion the user has to confirm or correct.
  final String? handleQuery;

  /// [messages] are the copy this device saved, not yet replaced by what
  /// central says: drawn while the conversation opens, and kept when it
  /// cannot.
  final bool showingSaved;

  /// The last thing to tell the person, shown once by `NoticeListeners`.
  final Notice? notice;

  const CentralDmState({
    this.status = CentralDmStatus.signedOut,
    this.myHandle,
    this.claiming = false,
    this.conversations = const [],
    this.conversationsLoading = false,
    this.hasMoreConversations = false,
    this.unreadByPeer = const {},
    this.levelsByPeer = const {},
    FriendBuckets? friends,
    this.openBuckets = const [],
    this.quota,
    this.remaining,
    this.friendsOpen = false,
    this.openPeerId,
    this.openPeerHandle,
    this.openPeerState,
    this.chatStatus = DmChatStatus.closed,
    this.messages = const [],
    this.hasMoreHistory = false,
    this.isLoadingMore = false,
    this.hasNewerHistory = false,
    this.error,
    this.loadFailed = false,
    this.handleQuery,
    this.showingSaved = false,
    this.notice,
  }) : friends = friends ?? FriendBuckets.empty;

  CentralDmState copyWith({
    CentralDmStatus? status,
    String? myHandle,
    bool? claiming,
    List<DmConversation>? conversations,
    bool? conversationsLoading,
    bool? hasMoreConversations,
    Map<String, int>? unreadByPeer,
    Map<String, NotificationLevel>? levelsByPeer,
    FriendBuckets? friends,
    List<FriendBucket>? openBuckets,
    int? quota,
    int? remaining,
    bool? friendsOpen,
    String? openPeerId,
    String? openPeerHandle,
    FriendshipState? openPeerState,
    bool clearOpenPeerState = false,
    DmChatStatus? chatStatus,
    List<ChatMessage>? messages,
    bool? hasMoreHistory,
    bool? isLoadingMore,
    bool? hasNewerHistory,
    String? error,
    bool? loadFailed,
    String? handleQuery,
    bool clearError = false,
    bool clearHandleQuery = false,
    bool closeConversation = false,
    bool? showingSaved,
    Notice? notice,
  }) {
    return CentralDmState(
      status: status ?? this.status,
      myHandle: myHandle ?? this.myHandle,
      claiming: claiming ?? this.claiming,
      conversations: conversations ?? this.conversations,
      conversationsLoading: conversationsLoading ?? this.conversationsLoading,
      hasMoreConversations: hasMoreConversations ?? this.hasMoreConversations,
      unreadByPeer: unreadByPeer ?? this.unreadByPeer,
      levelsByPeer: levelsByPeer ?? this.levelsByPeer,
      friends: friends ?? this.friends,
      openBuckets: openBuckets ?? this.openBuckets,
      quota: quota ?? this.quota,
      remaining: remaining ?? this.remaining,
      // Deliberately untouched by [closeConversation]: opening friends *is*
      // closing the conversation, and clearing it here would make the two
      // arguments fight in the one call that passes both.
      friendsOpen: friendsOpen ?? this.friendsOpen,
      openPeerId: closeConversation ? null : (openPeerId ?? this.openPeerId),
      openPeerHandle: closeConversation
          ? null
          : (openPeerHandle ?? this.openPeerHandle),
      openPeerState: closeConversation || clearOpenPeerState
          ? null
          : (openPeerState ?? this.openPeerState),
      chatStatus: closeConversation
          ? DmChatStatus.closed
          : (chatStatus ?? this.chatStatus),
      messages: closeConversation ? const [] : (messages ?? this.messages),
      hasMoreHistory: closeConversation
          ? false
          : (hasMoreHistory ?? this.hasMoreHistory),
      isLoadingMore: closeConversation
          ? false
          : (isLoadingMore ?? this.isLoadingMore),
      hasNewerHistory: closeConversation
          ? false
          : (hasNewerHistory ?? this.hasNewerHistory),
      error: clearError ? null : (error ?? this.error),
      loadFailed: closeConversation ? false : (loadFailed ?? this.loadFailed),
      handleQuery: clearHandleQuery ? null : (handleQuery ?? this.handleQuery),
      showingSaved: closeConversation
          ? false
          : (showingSaved ?? this.showingSaved),
      notice: notice ?? this.notice,
    );
  }

  NotificationLevel levelFor(String peerId) =>
      levelsByPeer[peerId] ?? NotificationLevel.dmDefault;

  /// Where the caller stands with one person — see [FriendshipState].
  ///
  /// The conversation row is the authoritative answer:
  /// `dm_conversations` resolves it per peer, so the client no longer holds the
  /// whole graph to work it out. Somebody reached from the friends page before
  /// a message has ever been exchanged with them has no row yet, and for the
  /// open one [openPeerState] answers. The friends tabs were that answer, and
  /// every change to the graph drops their pages: accepting a request from
  /// the open conversation left it saying "not friends", and any graph event
  /// swapped a friend's composer for that note, typed words and all. Whichever
  /// tab is open is the last resort, for a peer that is not open.
  ///
  /// A scan rather than a map, because this is asked about *one* peer: the
  /// open conversation. A row in the list has its own state on it and reads it
  /// there, without coming through here at all.
  FriendshipState stateFor(String peerId) {
    for (final conversation in conversations) {
      if (conversation.peerId == peerId) {
        return conversation.state ?? FriendshipState.none;
      }
    }
    final asked = peerId == openPeerId ? openPeerState : null;
    return asked ?? friends.stateOf(peerId) ?? FriendshipState.none;
  }

  /// Whether the open conversation can be typed into — which is to say
  /// whether the two of you are friends. Nothing else opens a composer.
  bool get canSendToOpen {
    final peerId = openPeerId;
    return peerId == null || stateFor(peerId).canSend;
  }

  /// Every unread central DM, **minus muted conversations and minus blocked
  /// peers**.
  ///
  /// A muted conversation keeps its own count: it still shows that something
  /// arrived in it. What muting buys is that it stops adding to the number on
  /// the outside, which is a claim that somebody wants you.
  ///
  /// A blocked peer needs no clause here any more: `dm_conversations` leaves
  /// them out of the list, so their unread counts never arrive to be skipped.
  int get totalUnread {
    var total = 0;
    for (final entry in unreadByPeer.entries) {
      if (levelFor(entry.key).isMuted) continue;
      total += entry.value;
    }
    return total;
  }

  /// What the rail's Home chip shows: unread messages plus people waiting for
  /// an answer. Somebody who has asked to reach you is exactly as worth
  /// surfacing as somebody who already can.
  int get homeBadge => totalUnread + friends.requestCount;

  @override
  List<Object?> get props => [
    status,
    myHandle,
    claiming,
    conversations,
    conversationsLoading,
    hasMoreConversations,
    unreadByPeer,
    levelsByPeer,
    friends,
    openBuckets,
    quota,
    remaining,
    friendsOpen,
    openPeerId,
    openPeerHandle,
    openPeerState,
    chatStatus,
    messages,
    hasMoreHistory,
    isLoadingMore,
    hasNewerHistory,
    error,
    loadFailed,
    handleQuery,
    showingSaved,
    notice,
  ];
}
