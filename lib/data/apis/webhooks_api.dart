import '../classes/webhook.dart';
import '../repositories/server_repository.dart';
import '../repositories/session_repository.dart';

/// Webhook management for a named server, or the selected one (BOTS.md §7).
///
/// Nothing here is kept in a cubit. A webhook list is read when a dialog
/// opens and thrown away when it closes — there is no badge, no sidebar entry
/// and no live view that would go stale, so holding it in cubit state would be
/// state kept for its own sake.
///
/// Holds nothing, so the dialog builds one from the session.
class WebhooksApi {
  final SessionRepository _session;

  WebhooksApi({required SessionRepository session}) : _session = session;

  ServerRepository get _repository => _session.repository;

  /// Every webhook posting into [channelId].
  Future<({List<Webhook> webhooks, String? error})> listWebhooks(
    String channelId, {
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (webhooks: <Webhook>[], error: 'No server');

    final response = await _session.callFor(
      server,
      (token) => _repository.listWebhooks(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) {
      return (
        webhooks: <Webhook>[],
        error: response.error ?? 'Could not load webhooks',
      );
    }

    final rows =
        (response.data as Map<String, dynamic>)['webhooks'] as List? ??
        const [];
    return (
      webhooks: [
        for (final r in rows.cast<Map<String, dynamic>>()) Webhook.fromJson(r),
      ],
      error: null,
    );
  }

  /// Mint a webhook and return its URL — the only time that URL exists.
  ///
  /// The URL is assembled here rather than by the database, because the
  /// database does not know what address a client reached it on. That is also
  /// why it is built from `server.supabaseUrl`: whatever this client used to
  /// get here is, by construction, an address that works.
  Future<({WebhookSecret? created, String? error})> createWebhook({
    required String channelId,
    required String name,
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (created: null, error: 'No server');

    final response = await _session.callFor(
      server,
      (token) => _repository.createWebhook(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        channelId: channelId,
        name: name,
      ),
    );
    if (!response.success) {
      return (created: null, error: response.error ?? 'Could not create that');
    }

    final data = response.data as Map<String, dynamic>;
    final reason = data['reason'] as String?;
    if (reason != 'ok') {
      return (created: null, error: _createFailure(reason));
    }

    final base = server.supabaseUrl.replaceAll(RegExp(r'/+$'), '');
    return (
      created: WebhookSecret(
        id: data['id'] as String,
        url: '$base/functions/v1/webhook/${data['secret']}',
      ),
      error: null,
    );
  }

  static String _createFailure(String? reason) => switch (reason) {
    'forbidden' => 'You cannot manage this channel',
    'no_such_channel' => 'That channel is gone',
    'bad_name' => 'Give it a name',
    'too_many' => 'This channel already has the maximum number of webhooks',
    _ => 'Could not create that webhook',
  };

  /// Revoke one. Its messages stay in the channel.
  Future<({bool success, String? error})> deleteWebhook(
    String id, {
    String? serverId,
  }) async {
    final server = _session.target(serverId);
    if (server == null) return (success: false, error: 'No server');

    final response = await _session.callFor(
      server,
      (token) => _repository.deleteWebhook(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: token,
        webhookId: id,
      ),
    );
    return (
      success: response.success,
      error: response.success
          ? null
          : response.error ?? 'Could not delete that webhook',
    );
  }
}
