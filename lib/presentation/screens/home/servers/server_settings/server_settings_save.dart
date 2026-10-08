import '../../../../../data/apis/invites_api.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import 'listing_actions.dart';
import 'listing_draft.dart';

/// All of Save, in the order that matters: the server's own settings first, then
/// its row in the central directory.
///
/// A named place for the sequence, because the order is the interesting part.
/// The settings live in the server's own project and are written on the server's
/// JWT; the listing lives on central under the user's Rift account. Doing them
/// this way round means a central outage can never cost the settings, and the two
/// halves fail as two different sentences instead of one "Saved" that isn't true.
class ServerSettingsSave {
  /// Returns null when everything landed, or the sentence to show when it didn't.
  ///
  /// Neither the operator limits nor the LiveKit connection are here: they are
  /// the Limits and Regions pages', and each saves its own — `update_server`
  /// leaves out what it isn't sent, so the three pages cannot tread on each
  /// other.
  static Future<String?> run({
    required Server server,
    required String name,
    required ListingDraft draft,
    required ServerCubit serverCubit,
    required InvitesApi invites,
    required PublicServersCubit publicServers,
    required int memberCount,
  }) async {
    final result = await serverCubit.updateServerDetails(
      name: name,
      // Named, because this dialog is not always about the selected server.
      serverId: server.id,
    );
    if (!result.success) return result.error ?? 'Failed to update server';

    return ListingActions.save(
      server: server,
      name: name,
      draft: draft,
      serverCubit: serverCubit,
      invites: invites,
      publicServers: publicServers,
      memberCount: memberCount,
    );
  }
}
