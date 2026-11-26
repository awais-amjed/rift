import '../enums/error_code.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';
import 'channels_api.dart';

/// The private half of a channel's life on a server: who is in it,
/// who may say so, and how a channel crosses the line in either direction.
///
/// Apart from [ChannelsApi] rather than in it, because these share something
/// the others do not. Every one of them is about a list of *people*, and under
/// end-to-end encryption that list is not a rule the server applies — it is
/// the set a key gets sealed to (ARCHITECTURE.md §4). Renaming a channel and
/// deciding who may read it are not the same kind of act, and the second one
/// cannot be undone by changing your mind.
///
/// Holds nothing, so a widget builds one from the session.
class ChannelAccessApi {
  final ServerSession _target;

  ChannelAccessApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Seat [add] and remove [remove] in a private channel, and nobody else.
  ///
  /// By name rather than as the whole list, so a seat the caller never saw —
  /// a read cut short, a name that did not resolve, somebody who left while
  /// the page was open — is never removed or put back by accident. Removing
  /// the last member deletes the channel, and that is not an accident to be
  /// guarded against here: nobody outside can see a private channel, so
  /// nobody outside could be asked to tidy up an empty one.
  ///
  /// A voice channel's goes through the `change_channel_members` function,
  /// which also takes whoever was removed out of a call running there; a
  /// text channel's is the RPC of that name, since it has no call. A server
  /// from before either gets the old whole-list write, built from [seated] —
  /// the read the change was made against, which has to be complete for that
  /// to be safe.
  Future<({bool success, String? error})> changeChannelMembers({
    required String channelId,
    required bool isVoice,
    required Set<String> add,
    required Set<String> remove,
    required Set<String> seated,
  }) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);
    const failure = 'Failed to update who is in this channel';

    var response = await _session.callFor(
      server,
      (token) => isVoice
          ? _repository.changeChannelMembers(
              server.supabaseUrl,
              channelId,
              bearerToken: token,
              add: add.toList(),
              remove: remove.toList(),
            )
          : _repository.changeChannelMembersRpc(
              server.supabaseUrl,
              channelId,
              anonKey: server.supabaseKey ?? '',
              bearerToken: token,
              add: add.toList(),
              remove: remove.toList(),
            ),
    );
    if (response.errorCode == ErrorCode.functionMissing ||
        response.errorCode == 'PGRST202') {
      response = await _session.callFor(
        server,
        (token) => _repository.setChannelMembers(
          server.supabaseUrl,
          channelId,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
          userIds: {...seated.difference(remove), ...add}.toList(),
        ),
      );
    }
    if (!response.success) {
      return (success: false, error: channelRefusal(response, failure));
    }
    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (
        success: false,
        error: reason == 'no_such_channel'
            ? 'That channel is gone, or no longer private'
            : failure,
      );
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// Open a channel up, or close it.
  ///
  /// Closing seats everybody who is currently on the server, so the room does
  /// not empty out under the people already talking in it; narrowing it down is
  /// a second call to [changeChannelMembers]. Opening leaves a rotation behind, so
  /// the private history stays unreadable to whoever arrives next.
  Future<({bool success, String? error})> setChannelPrivate({
    required String channelId,
    required bool isPrivate,
  }) => changeChannel(
    _target,
    (server, token) => _repository.setChannelPrivate(
      server.supabaseUrl,
      channelId,
      anonKey: server.supabaseKey ?? '',
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
  }) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);
    final failure = encrypted
        ? 'Failed to turn encryption back on'
        : 'Failed to turn encryption off';

    final response = await _session.callFor(
      server,
      (token) => _repository.setChannelEncrypted(
        server.supabaseUrl,
        channelId,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        encrypted: encrypted,
      ),
    );
    if (!response.success) {
      return (success: false, error: channelRefusal(response, failure));
    }
    // A refusal that is not an exception: the channel went private, or became
    // a voice one, while the confirm was open.
    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != null && reason != 'ok') {
      await _session.refreshDetails(server);
      return (
        success: false,
        error: reason == 'not_public_text'
            ? 'Only a public text channel can go unencrypted'
            : failure,
      );
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// Walk out of a private channel.
  ///
  /// Not [changeChannelMembers] removing your own name — that needs the manage bit,
  /// which is the right answer for who *else* is in a room and the wrong one
  /// for whether you are. Leaving needs nobody's permission.
  Future<({bool success, String? error})> leaveChannel(
    String channelId, {
    required bool isVoice,
  }) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);

    // A voice channel through the function, so its call is left on the
    // server's side too; a text one, and a server from before the function,
    // straight to the RPC.
    var response = isVoice
        ? await _session.callFor(
            server,
            (token) => _repository.leaveChannelAndCall(
              server.supabaseUrl,
              channelId,
              bearerToken: token,
            ),
          )
        : null;
    if (response == null || response.errorCode == ErrorCode.functionMissing) {
      response = await _session.callFor(
        server,
        (token) => _repository.leaveChannel(
          server.supabaseUrl,
          channelId,
          anonKey: server.supabaseKey ?? '',
          bearerToken: token,
        ),
      );
    }
    if (!response.success) {
      return (
        success: false,
        error: channelRefusal(response, 'Could not leave'),
      );
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (success: false, error: _leaveFailure(reason as String?));
    }

    await _session.refreshDetails(server);
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

  /// Who is in [channelId], and whether this device may change that; null
  /// when the read failed.
  ///
  /// Both answers come out of the same rows, which is the reason they are one
  /// call: `can_manage` is a property of *my* membership, and a private
  /// channel's manager is somebody inside it rather than whoever holds
  /// `MANAGE_CHANNELS` on the server — those people cannot see the room at all.
  ///
  /// Empty for a public channel, and for a private one the caller cannot see.
  /// Those are the same answer on purpose. A failed read is not: drawn as
  /// nobody, it offered a Save that removed everybody.
  Future<({Set<String> memberIds, bool canManage})?> channelMembers(
    String channelId,
  ) async {
    final server = _target.server;
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.listChannelMembers(
        server.supabaseUrl,
        channelId,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) return null;

    final rows =
        ((response.data as Map<String, dynamic>)['members'] as List? ??
                const [])
            .cast<Map<String, dynamic>>();
    final me = server.user?.id;
    return (
      memberIds: {for (final r in rows) r['user_id'] as String},
      canManage: rows.any((r) => r['user_id'] == me && r['can_manage'] == true),
    );
  }
}
