part of 'server_cubit.dart';

/// Webhook management for the selected server (BOTS.md §7).
///
/// Nothing here touches [ServerState]. A webhook list is read when a dialog
/// opens and thrown away when it closes — there is no badge, no sidebar entry
/// and no live view that would go stale, so holding it in cubit state would be
/// state kept for its own sake.
mixin _ServerWebhooksApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  String get _anonKey;

  Future<APIResponse> _callWithAutoRefresh(
    Future<APIResponse> Function(String token) call,
  );

  /// Every webhook posting into [channelId].
  Future<({List<Webhook> webhooks, String? error})> listWebhooks(
    String channelId,
  ) async {
    final server = state.selectedServer;
    if (server == null) return (webhooks: <Webhook>[], error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.listWebhooks(
        server.supabaseUrl,
        anonKey: _anonKey,
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
  }) async {
    final server = state.selectedServer;
    if (server == null) return (created: null, error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.createWebhook(
        server.supabaseUrl,
        anonKey: _anonKey,
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
  Future<({bool success, String? error})> deleteWebhook(String id) async {
    final server = state.selectedServer;
    if (server == null) return (success: false, error: 'No server');

    final response = await _callWithAutoRefresh(
      (token) => _repository.deleteWebhook(
        server.supabaseUrl,
        anonKey: _anonKey,
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

  /// The bots holding a key to [channelId], by display name.
  ///
  /// Read on channel open and shown in the header, not behind a menu: a
  /// standing marker is the point (BOTS.md §6, rule 4). A dialog somebody has
  /// to go looking for tells the people who already knew.
  Future<List<String>> channelListeners(String channelId) async {
    final server = state.selectedServer;
    if (server == null) return const [];

    final response = await _callWithAutoRefresh(
      (token) => _repository.listChannelListeners(
        server.supabaseUrl,
        anonKey: _anonKey,
        bearerToken: token,
        channelId: channelId,
      ),
    );
    if (!response.success) return const [];

    final rows =
        (response.data as Map<String, dynamic>)['listeners'] as List? ??
        const [];
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (r['display_name'] as String?) ?? (r['username'] as String? ?? 'a bot'),
    ];
  }
}
