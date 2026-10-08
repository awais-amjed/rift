import '../classes/api_response.dart';
import '../classes/server.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Channel create / update / delete / reorder on the selected server.
///
/// Every one of them changes the channel list, and so ends by bringing
/// *everyone's* sidebar back in line: our own by re-reading the server
/// ([SessionRepository.refreshDetails], landed before the call answers), and
/// every other member's through `channels_announce` on the row itself, which
/// reaches members who were offline and members nobody could ring.
///
/// Who may read a channel is `ChannelAccessApi`'s.
///
/// Holds nothing, so a widget builds one from the session.
class ChannelsApi {
  final SessionRepository _session;

  ChannelsApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Create a new channel.
  ///
  /// [memberIds] is only read when [isPrivate], and never has to include the
  /// creator: `create_channel` seats them itself.
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
    bool isPrivate = false,
    List<String> memberIds = const [],
  }) async {
    final server = _session.selectedServer;
    if (server == null) return (success: false, error: _session.noTarget(null));

    final response = await _session.callFor(
      server,
      (token) => _repository.createChannel(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        name: name,
        channelType: channelType,
        isPrivate: isPrivate,
        memberIds: isPrivate ? memberIds : const [],
      ),
    );
    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to create channel',
      );
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (success: false, error: _createFailure(reason as String?));
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  /// Change a channel's name, its retention overrides, or which LiveKit its
  /// calls are held on (channel manager only).
  ///
  /// An override omitted leaves that column alone; the matching `clear…` flag
  /// puts the channel back to inheriting the server's number — or, for
  /// [livekitNodeId], back to picking a node automatically.
  Future<({bool success, String? error})> updateChannel({
    required String channelId,
    String? name,
    int? retentionDays,
    bool clearRetentionDays = false,
    int? historyCap,
    bool clearHistoryCap = false,
    String? livekitNodeId,
    bool clearLivekitNodeId = false,
  }) => changeChannel(
    _session,
    (server, token) => _repository.updateChannel(
      server.supabaseUrl,
      channelId,
      anonKey: server.supabaseKey ?? '',
      bearerToken: token,
      name: name,
      retentionDays: retentionDays,
      clearRetentionDays: clearRetentionDays,
      historyCap: historyCap,
      clearHistoryCap: clearHistoryCap,
      livekitNodeId: livekitNodeId,
      clearLivekitNodeId: clearLivekitNodeId,
    ),
    failure: 'Failed to update channel',
  );

  /// Delete a channel (channel manager only). Anyone in its call is dropped —
  /// see [ServerRepository.deleteChannel].
  Future<({bool success, String? error})> deleteChannel(String channelId) =>
      changeChannel(
        _session,
        (server, token) => _repository.deleteChannel(
          server.supabaseUrl,
          channelId,
          bearerToken: token,
        ),
        failure: 'Failed to delete channel',
      );

  /// Put one section's channels in the order given (`MANAGE_CHANNELS`).
  ///
  /// Everyone else's sidebar follows from the single `channels` ring the
  /// function sends; ours is re-read here, so the caller can stop showing the
  /// order it dropped the moment this returns.
  Future<({bool success, String? error})> reorderChannels(
    List<String> channelIds,
  ) async {
    final server = _session.selectedServer;
    if (server == null) return (success: false, error: _session.noTarget(null));

    final response = await _session.callFor(
      server,
      (token) => _repository.reorderChannels(
        server.supabaseUrl,
        channelIds,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    // Re-read on a refusal too: it usually means the list we dragged was
    // already out of date.
    await _session.refreshDetails(server);
    if (!response.success) {
      return (success: false, error: _reorderFailure(response.errorCode));
    }
    return (success: true, error: null);
  }

  static String _reorderFailure(String? code) => switch (code) {
    'not_authorized' => "You can't reorder channels here",
    'channel_not_found' => 'The channels changed. Try again.',
    // PostgREST's "no such function": a server from before 010.
    'PGRST202' => 'This server needs an update to reorder channels',
    _ => "Couldn't reorder the channels",
  };

  static String _createFailure(String? reason) => switch (reason) {
    'name_taken' => 'A channel already has that name',
    'not_authorized' => 'You cannot create channels here',
    'bad_name' => 'Give it a name',
    _ => 'Failed to create channel',
  };
}

/// Run a channel write on the selected server, then re-read the server so our
/// own channel list holds the change before this answers. Shared with
/// `ChannelAccessApi`, whose writes end the same way.
Future<({bool success, String? error})> changeChannel(
  SessionRepository session,
  Future<APIResponse> Function(Server server, String token) call, {
  required String failure,
}) async {
  final server = session.selectedServer;
  if (server == null) return (success: false, error: session.noTarget(null));

  final response = await session.callFor(
    server,
    (token) => call(server, token),
  );
  if (!response.success) {
    return (success: false, error: response.error ?? failure);
  }

  await session.refreshDetails(server);
  return (success: true, error: null);
}
