part of 'central_dm_repository.dart';

/// The `notification_prefs` table: how much each conversation may interrupt.
///
/// Server-side rather than local for the same reason the read cursors are —
/// muting somebody on a phone should mute them on the desktop too, and a
/// setting that only holds on the device you set it on is a setting people
/// stop trusting. RLS is own-row, so nobody learns that they have been muted.
///
/// The same table, with the same `scope`/`scope_id` shape, is what a
/// self-hosted server uses for its channels and DMs (`notification_prefs`
/// on both).
mixin _CentralDmPrefsMixin {
  SupabaseClient get _client;

  /// Set one conversation's level.
  ///
  /// There is no read here any more. Reading every row of this table to draw
  /// the rows already on screen was a whole-table fetch of something that grows
  /// with the number of conversations, so the level rides on the conversation
  /// row instead. A conversation nobody has an opinion
  /// about carries a null level, which is what lets the default be changed
  /// later without rewriting anybody's table.
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
