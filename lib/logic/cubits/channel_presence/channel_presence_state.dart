part of 'channel_presence_cubit.dart';

/// Somebody sitting in a voice channel, as the sidebar lists them.
class PresenceUser extends Equatable {
  final String userId;
  final String displayName;

  const PresenceUser({required this.userId, required this.displayName});

  @override
  List<Object?> get props => [userId, displayName];
}

/// Who is online on the selected server, and which voice channel each is in.
class ChannelPresenceState extends Equatable {
  /// Maps channelId → who is in that voice channel, by display name.
  ///
  /// Built from the broadcast locations, filtered by [onlineUserIds] and with
  /// the local user left out — see `ChannelPresenceCubit._emit`.
  final Map<String, List<PresenceUser>> channelPresence;

  /// Everyone with the app open on this server, whether or not they're in a
  /// voice channel — including the local user. Drives the member sidebar's
  /// online/offline split.
  final Set<String> onlineUserIds;

  /// channelId → when the call there began, for every occupied channel —
  /// our own included, unlike [channelPresence].
  final Map<String, DateTime> callStartedAt;

  /// How busy each of this server's voice regions is, keyed by node id, as
  /// the last roster read reported it — what a channel manager sees beside
  /// each region when choosing one.
  ///
  /// A reading seconds old, empty until the first read answers. Here because
  /// the roster read is this cubit's; the token request weighs the same
  /// reading from `SessionRepository.regionProbe`, which is where it lands.
  final Map<String, RegionLoad> regionLoad;

  const ChannelPresenceState({
    this.channelPresence = const {},
    this.onlineUserIds = const {},
    this.callStartedAt = const {},
    this.regionLoad = const {},
  });

  List<PresenceUser> usersIn(String channelId) =>
      channelPresence[channelId] ?? const [];

  /// The voice channel [userId] is in, or null if they're in none.
  ///
  /// Never answers for the local user — we're deliberately left out of the
  /// per-channel roster, so ask [LiveKitState] for yourself.
  String? channelOf(String userId) {
    for (final entry in channelPresence.entries) {
      if (entry.value.any((user) => user.userId == userId)) return entry.key;
    }
    return null;
  }

  /// Whether [userId] has told us they are in a voice channel that isn't
  /// [channelId].
  ///
  /// The channel you're *in* draws its roster from LiveKit rather than from
  /// here, because that's what carries speaking and mute state — so a member
  /// who leaves it lingers until the SFU gets round to mentioning it, while
  /// their own broadcast has already put them somewhere else. For that gap they
  /// are drawn in two channels at once. Their broadcast is the newer fact, so
  /// it wins.
  ///
  /// Only ever true when we have a positive location for them: someone we
  /// simply haven't heard from stays where LiveKit says they are.
  bool isElsewhere(String userId, String channelId) {
    final known = channelOf(userId);
    return known != null && known != channelId;
  }

  bool isOnline(String userId) => onlineUserIds.contains(userId);

  @override
  List<Object?> get props => [
    channelPresence,
    SetProp(onlineUserIds),
    callStartedAt,
    regionLoad,
  ];
}
