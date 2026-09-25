part of 'central_dm_repository.dart';

/// Pins in a central DM. Either of the two may pin; `set_pinned` holds the
/// fifty-a-conversation cap. The server knows which messages are pinned,
/// never what they say — the same trade as a self-hosted server's DM pins.
mixin _CentralDmPinsMixin {
  SupabaseClient get _client;

  /// The embed every DM read carries, so a message knows it is pinned.
  static const pinEmbed = 'dm_message_pins(pinned_at)';

  /// Lift the embedded pin (an object or null) to `pinned_at` on the row.
  static Map<String, dynamic> liftPin(Map<String, dynamic> row) {
    final pin = row.remove('dm_message_pins');
    return {...row, 'pinned_at': pin is Map ? pin['pinned_at'] : null};
  }

  Future<APIResponse> setPinned({
    required int messageId,
    required bool pinned,
  }) async {
    try {
      await _client.rpc(
        'set_pinned',
        params: {'p_message': messageId, 'p_pinned': pinned},
      );
      return APIResponse.success(null);
    } on PostgrestException catch (e) {
      return _rpcFailure(e, const ['pin_limit', 'message_not_found']);
    } catch (e) {
      return APIResponse.error(e);
    }
  }

  /// The pinned rows of the DM with [peerId], newest pin first, as
  /// `{messages: [...]}`.
  Future<APIResponse> listPins({required String peerId}) async {
    try {
      final myId = _client.auth.currentUser!.id;
      final pair = [myId, peerId]..sort();
      final rows = await _client
          .from('dm_message_pins')
          .select('pinned_at, dm_messages!inner(*, $pinEmbed)')
          .eq('user_low', pair.first)
          .eq('user_high', pair.last)
          .order('pinned_at', ascending: false)
          .limit(50);
      return APIResponse.success({
        'messages': [
          for (final row in (rows as List).cast<Map<String, dynamic>>())
            liftPin((row['dm_messages'] as Map).cast<String, dynamic>()),
        ],
      });
    } catch (e) {
      return APIResponse.error(e);
    }
  }
}
