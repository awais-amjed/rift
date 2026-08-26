part of 'central_dm_repository.dart';

/// The `notification_prefs` table: how much each conversation may interrupt.
///
/// Server-side rather than local for the same reason the read cursors are —
/// muting somebody on a phone should mute them on the desktop too, and a
/// setting that only holds on the device you set it on is a setting people
/// stop trusting. RLS is own-row, so nobody learns that they have been muted.
///
/// The same table, with the same `scope`/`scope_id` shape, is what a
/// self-hosted server uses for its channels and DMs (migration 012 there,
/// 011 here).
mixin _CentralDmPrefsMixin {
  SupabaseClient get _client;

  /// Every conversation the caller has an opinion about: `{peerId: level}`.
  ///
  /// Conversations they don't are simply absent — [NotificationLevel.dmDefault]
  /// answers for those, and that is what lets the default be changed later
  /// without rewriting everybody's rows.
  Future<APIResponse> listNotificationLevels() async {
    try {
      final rows = await _client
          .from('notification_prefs')
          .select('scope_id, level')
          .eq('user_id', _client.auth.currentUser!.id)
          .eq('scope', 'dm');
      final levels = <String, NotificationLevel>{};
      for (final row in (rows as List).cast<Map<String, dynamic>>()) {
        final peerId = row['scope_id'] as String?;
        if (peerId == null) continue;
        final level = NotificationLevel.parse(
          row['level'],
          fallback: NotificationLevel.dmDefault,
        );
        if (level != NotificationLevel.dmDefault) levels[peerId] = level;
      }
      return APIResponse.success(levels);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// Set one conversation's level.
  ///
  /// Choosing the default **deletes** the row instead of storing it: a scope
  /// nobody has an opinion about should have no row, so that what the default
  /// means stays one decision rather than a copy in every user's table.
  Future<APIResponse> setNotificationLevel({
    required String peerId,
    required NotificationLevel level,
  }) async {
    try {
      final userId = _client.auth.currentUser!.id;
      if (level == NotificationLevel.dmDefault) {
        await _client
            .from('notification_prefs')
            .delete()
            .eq('user_id', userId)
            .eq('scope', 'dm')
            .eq('scope_id', peerId);
      } else {
        await _client.from('notification_prefs').upsert({
          'user_id': userId,
          'scope': 'dm',
          'scope_id': peerId,
          'level': level.toJson(),
        }, onConflict: 'user_id,scope,scope_id');
      }
      return APIResponse.success(null);
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
