part of 'server_repository.dart';

/// The two things only an owner does (`transfer_ownership`, `delete_server`): hand the server on, and
/// end it.
///
/// Transfer is an RPC because the policies refuse the owner role in both
/// directions, on purpose, and the one write that moves it has to make the
/// checks they would have made. Deletion is an edge function because the row
/// delete is the easy half — the LiveKit rooms and the storage bucket need
/// the service role, exactly as with `delete_channel`.
mixin _OwnershipApiMixin {
  ServerDb get _db;

  Future<APIResponse> _post(
    String supabaseUrl,
    String functionName,
    Map<String, dynamic> body, {
    String? bearerToken,
  });

  Future<APIResponse> transferOwnership(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
    required String userId,
  }) {
    return ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      await db.rpc('transfer_ownership', params: {'p_user': userId});
      return const <String, dynamic>{};
    });
  }

  Future<APIResponse> deleteServer(String supabaseUrl, {String? bearerToken}) {
    return _post(
      supabaseUrl,
      'delete_server',
      const {},
      bearerToken: bearerToken,
    );
  }
}
