import 'dart:typed_data';

import '../../../../../data/apis/invites_api.dart';
import '../../../../../data/apis/server_api.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server_events/server_events_cubit.dart';
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
  /// [newIcon] is a picked picture, already prepared; [removeIcon] takes the
  /// icon away. The picture is uploaded before the row is written, and the
  /// row's update carries its path with the name, so a failed upload changes
  /// nothing at all.
  ///
  /// Neither the operator limits nor the LiveKit connection are here: they are
  /// the Limits and Regions pages', and each saves its own — `update_server`
  /// leaves out what it isn't sent, so the three pages cannot tread on each
  /// other.
  static Future<String?> run({
    required Server server,
    required String name,
    required ListingDraft draft,
    required ServerApi serverApi,
    required ServerEventsCubit events,
    required InvitesApi invites,
    required PublicServersCubit publicServers,
    required int memberCount,
    Uint8List? newIcon,
    bool removeIcon = false,
  }) async {
    var iconPath = removeIcon ? null : server.iconPath;
    String? uploaded;
    if (newIcon != null) {
      final upload = await serverApi.uploadIcon(newIcon);
      if (upload.path == null) {
        return upload.error ?? 'The icon could not be uploaded';
      }
      iconPath = uploaded = upload.path;
    }

    final result = await serverApi.updateServerDetails(
      name: name,
      iconPath: uploaded,
      clearIcon: removeIcon && uploaded == null,
    );
    if (!result.success) return result.error ?? 'Failed to update server';
    // A rename or a new icon shows in every member's rail, so they re-read
    // now.
    events.notifyServerChanged(server.id);

    return ListingActions.save(
      server: server,
      name: name,
      iconPath: iconPath,
      draft: draft,
      serverApi: serverApi,
      invites: invites,
      publicServers: publicServers,
      memberCount: memberCount,
    );
  }
}
