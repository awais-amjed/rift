import '../classes/channel.dart';
import '../classes/channel_override.dart';
import '../enums/channel_type.dart';
import '../repositories/server_repository.dart';
import '../repositories/server_session.dart';
import '../repositories/session_repository.dart';

/// A channel's own say over what each role may do in it
/// (`channel_overrides`), on one server.
///
/// The rules are the server's (`set_channel_override`): who may change a row,
/// which bits a channel of each kind can override, and that nobody moves a bit
/// they do not hold. A refusal comes back as words, not repeated here.
///
/// Holds nothing, so a widget builds one from the session.
class ChannelOverridesApi {
  final ServerSession _target;

  ChannelOverridesApi(this._target);

  SessionRepository get _session => _target.session;

  ServerRepository get _repository => _session.repository;

  /// Every role's row in [channelId], keyed by role. Null when the read
  /// failed, which is not the same answer as nothing overridden.
  Future<Map<String, ChannelOverride>?> list(String channelId) async {
    final server = _target.server;
    if (server == null) return null;

    final response = await _session.callFor(
      server,
      (token) => _repository.listChannelOverrides(
        server.supabaseUrl,
        channelId,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
      ),
    );
    if (!response.success) return null;

    final rows =
        (response.data as Map<String, dynamic>?)?['overrides'] as List? ??
        const [];
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        row['role_id'] as String: ChannelOverride.fromJson(row),
    };
  }

  /// Replace [override]'s row in [channel]; an empty one goes back to
  /// inheriting everything. Re-reads the server before answering, so the
  /// caller's own `myPermissions` already holds the change.
  ///
  /// A voice channel's goes through the edge function, so turning a call
  /// Listen-only takes the microphone of whoever is talking in it now, not
  /// at their next join.
  Future<({bool success, String? error})> set(
    Channel channel,
    ChannelOverride override,
  ) async {
    final server = _target.server;
    if (server == null) return (success: false, error: ServerSession.gone);

    final response = await _session.callFor(
      server,
      (token) => channel.channelType == ChannelType.voice
          ? _repository.setVoiceChannelOverride(
              server.supabaseUrl,
              channel.id,
              bearerToken: token,
              roleId: override.roleId,
              allow: override.allow,
              deny: override.deny,
            )
          : _repository.setChannelOverride(
              server.supabaseUrl,
              channel.id,
              anonKey: server.supabaseKey ?? '',
              bearerToken: token,
              roleId: override.roleId,
              allow: override.allow,
              deny: override.deny,
            ),
    );
    if (!response.success) {
      // A server from before overrides has no such function.
      return (
        success: false,
        error: response.errorCode == 'PGRST202'
            ? 'This server needs updating before channels can have their '
                  'own permissions'
            : response.error ?? 'Could not save that',
      );
    }

    final reason = (response.data as Map<String, dynamic>?)?['reason'];
    if (reason != 'ok') {
      return (success: false, error: _failure(reason as String?));
    }

    await _session.refreshDetails(server);
    return (success: true, error: null);
  }

  static String _failure(String? reason) => switch (reason) {
    'forbidden' =>
      'You can only change roles below your own, and only the permissions '
          'you hold yourself',
    'no_such_channel' => 'That channel is gone',
    'no_such_role' => 'That role is gone',
    'invalid' => 'That is not something this channel can change',
    _ => 'Could not save that',
  };
}
