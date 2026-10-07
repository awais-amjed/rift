part of 'server_cubit.dart';

/// The private half of a channel's life: who is in it, who may say so, and how
/// a channel crosses the line in either direction.
///
/// Split from [_ServerChannelsApiMixin] rather than sitting in it, because
/// these share something the other three do not. Every one of them is about a
/// list of *people*, and under end-to-end encryption that list is not a rule
/// the server applies — it is the set a key gets sealed to (ARCHITECTURE.md
/// §4). Renaming a channel and deciding who may read it are not the same kind
/// of act, and the second one cannot be undone by changing your mind.
mixin _ServerPrivateChannelsApiMixin on _ServerChannelsApiMixin {
  /// Replace a private channel's membership with exactly [userIds].
  ///
  /// Removing the last member deletes the channel, and that is not an accident
  /// to be guarded against here — nobody outside can see a private channel, so
  /// nobody outside could be asked to tidy up an empty one.
  Future<({bool success, String? error})> setChannelMembers({
    required String channelId,
    required List<String> userIds,
  }) => _changeChannel(
    (server, token) => _repository.setChannelMembers(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      userIds: userIds,
    ),
    failure: 'Failed to update who is in this channel',
  );

  /// Open a channel up, or close it.
  ///
  /// Closing seats everybody who is currently on the server, so the room does
  /// not empty out under the people already talking in it; narrowing it down is
  /// a second call to [setChannelMembers]. Opening leaves a rotation behind, so
  /// the private history stays unreadable to whoever arrives next.
  Future<({bool success, String? error})> setChannelPrivate({
    required String channelId,
    required bool isPrivate,
  }) => _changeChannel(
    (server, token) => _repository.setChannelPrivate(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      isPrivate: isPrivate,
    ),
    failure: isPrivate
        ? 'Failed to make this channel private'
        : 'Failed to open this channel up',
  );

  /// Turn a public text channel's encryption off, or back on.
  ///
  /// Here with privacy because it is the same kind of act: it decides who can
  /// read what is said, and off is the server.
  Future<({bool success, String? error})> setChannelEncrypted({
    required String channelId,
    required bool encrypted,
  }) => _changeChannel(
    (server, token) => _repository.setChannelEncrypted(
      server.supabaseUrl,
      channelId,
      anonKey: _anonKey,
      bearerToken: token,
      encrypted: encrypted,
    ),
    failure: encrypted
        ? 'Failed to turn encryption back on'
        : 'Failed to turn encryption off',
  );

  /// Walk out of a private channel.
  ///
  /// Not [setChannelMembers] with one name removed — that needs the manage bit,
  /// which is the right answer for who *else* is in a room and the wrong one
  /// for whether you are. Leaving needs nobody's permission.
  Future<({bool success, String? error})> leaveChannel(String channelId) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server selected');

    final response = await _callWithAutoRefresh(
      (token) => _repository.leaveChannel(
        server.supabaseUrl,
        channelId,
        anonKey: _anonKey,
        bearerToken: token,
      ),
    );
    if (!response.success) {
      return (success: false, error: response.error ?? 'Could not leave');
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (success: false, error: _leaveFailure(reason as String?));
    }

    await refreshServerDetails();
    return (success: true, error: null);
  }

  static String _leaveFailure(String? reason) => switch (reason) {
    'in_by_role' =>
      'You are in here through a role, so leaving would take everybody with '
          'that role out too. Ask whoever runs this channel.',
    'not_private' => 'This channel is open to the whole server',
    'no_such_channel' => 'That channel is gone',
    _ => 'Could not leave that channel',
  };

  /// Who is in [channelId], and whether this device may change that.
  ///
  /// Both answers come out of the same rows, which is the reason they are one
  /// call: `can_manage` is a property of *my* membership, and a private
  /// channel's manager is somebody inside it rather than whoever holds
  /// `MANAGE_CHANNELS` on the server — those people cannot see the room at all.
  ///
  /// Empty for a public channel, and for a private one the caller cannot see.
  /// Those are the same answer on purpose.
  Future<({Set<String> memberIds, bool canManage})> channelMembers(
    String channelId,
  ) async {
    final server = state.selectedServer;
    if (server == null) return (memberIds: <String>{}, canManage: false);

    final response = await _callWithAutoRefresh(
      (token) => _repository.listChannelMembers(
        server.supabaseUrl,
        channelId,
        anonKey: _anonKey,
        bearerToken: token,
      ),
    );
    if (!response.success) {
      return (memberIds: <String>{}, canManage: false);
    }

    final rows =
        (response.data as Map<String, dynamic>)['members'] as List? ?? const [];
    final me = server.user?.id;
    return (
      memberIds: {
        for (final r in rows.cast<Map<String, dynamic>>())
          r['user_id'] as String,
      },
      canManage: rows.cast<Map<String, dynamic>>().any(
        (r) => r['user_id'] == me && r['can_manage'] == true,
      ),
    );
  }
}
