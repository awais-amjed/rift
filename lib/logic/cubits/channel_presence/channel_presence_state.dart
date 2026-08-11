part of 'channel_presence_cubit.dart';

class PresenceUser {
  final String userId;
  final String displayName;

  const PresenceUser({required this.userId, required this.displayName});
}

class ChannelPresenceState {
  /// Maps channelId → who is in that voice channel, by display name.
  ///
  /// Built from the broadcast locations, filtered by [onlineUserIds] and with
  /// the local user left out — see `ChannelPresenceCubit._emit`.
  final Map<String, List<PresenceUser>> channelPresence;

  /// Everyone with the app open on this server, whether or not they're in a
  /// voice channel — including the local user. Drives the member sidebar's
  /// online/offline split.
  final Set<String> onlineUserIds;

  const ChannelPresenceState({
    this.channelPresence = const {},
    this.onlineUserIds = const {},
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

  bool isOnline(String userId) => onlineUserIds.contains(userId);
}
