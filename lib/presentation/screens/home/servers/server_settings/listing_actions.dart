import 'package:flutter/material.dart';

import '../../../../../data/apis/invites_api.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/confirm_dialog.dart';
import 'listing_draft.dart';

/// The central-server side of the server settings dialog.
///
/// Its own file because it is the odd half: everything else in that dialog
/// goes to the server's own project on its JWT, and this goes to central on
/// the user's Rift account. Keeping the two-database seam in one named place
/// is what stops the dialog reading as though it were one write.
class ListingActions {
  /// The directory half of Save, run after the server's own update — see
  /// [ServerSettingsSave], which owns that order.
  ///
  /// Returns null on success, or the sentence to show when the settings saved
  /// and the listing did not — the outcome a single "Saved" would have lied
  /// about.
  static Future<String?> save({
    required Server server,
    required String name,
    required ListingDraft draft,
    required ServerCubit serverCubit,
    required InvitesApi invites,
    required PublicServersCubit publicServers,
    required int memberCount,
  }) async {
    if (!draft.touchesDirectory) return null;

    // Proof that an admin of this server asked for the listing, before
    // anything is minted. Central cannot tell an administrator from any other
    // member, so it redeems this against the server's own domain before
    // writing anything.
    final proof = await serverCubit.listingToken(serverId: server.id);
    if (proof.token == null) {
      return 'Server settings saved, but the public listing did not: '
          '${proof.error ?? 'this server would not confirm it.'}';
    }

    final minted = await _inviteCode(draft, invites, server.id);
    final code = minted.code;
    if (code == null) {
      return 'Server settings saved, but the listing needs a join link and '
          'one could not be created. Try Save again.';
    }

    final saved = await publicServers.publish(
      supabaseUrl: server.supabaseUrl,
      serverId: server.id,
      inviteCode: code,
      listingToken: proof.token!,
      // The listing is named by the server, so a rename reaches the directory
      // in the same Save that applied it.
      name: name,
      description: draft.description,
      iconSourceUrl: server.iconUrl,
      tags: draft.tags,
      memberCount: memberCount,
      isListed: draft.isListed,
    );
    if (saved == null) {
      // A link minted for a listing that did not happen points at nothing and
      // never expires. The one the listing already had is left alone — it is
      // still in use by the row that is still there.
      if (minted.isNew) {
        await invites.revokeInvite(inviteCode: code, serverId: server.id);
      }
      return 'Server settings saved, but the public listing did not: '
          '${publicServers.state.error ?? 'central could not be reached.'}';
    }
    draft.listing = saved;
    return null;
  }

  /// Withdraw the listing, after asking. Unlike the toggle — which delists and
  /// keeps the row, its code and its copy — this keeps nothing, so it acts on
  /// its own rather than waiting for Save.
  ///
  /// Returns whether anything happened and what to show: a cancelled confirm
  /// is `(removed: false, error: null)`.
  static Future<({bool removed, String? error})> remove(
    BuildContext context, {
    required ListingDraft draft,
    required PublicServersCubit publicServers,
  }) async {
    final listing = draft.listing;
    if (listing == null) return (removed: false, error: null);

    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove this listing?',
      message:
          'The server stays exactly as it is — it just stops being findable. '
          'Anyone already holding its join link can still use it until you '
          'revoke that invite under Invite people.',
      confirmLabel: 'Remove',
      icon: Icons.public_off_outlined,
      isDestructive: true,
    );
    if (!confirmed) return (removed: false, error: null);

    if (!await publicServers.remove(listing.id)) {
      return (removed: false, error: publicServers.state.error);
    }
    draft.seed(null);
    return (removed: true, error: null);
  }

  /// The invite code the listing will carry: the one it already has, or a
  /// fresh unlimited-use, permissionless invite minted on the server itself.
  ///
  /// [isNew] says which, because only a link minted here may be taken back
  /// when the publish fails.
  static Future<({String? code, bool isNew})> _inviteCode(
    ListingDraft draft,
    InvitesApi invites,
    String serverId,
  ) async {
    final existing = draft.listing?.inviteCode;
    if (existing != null && !draft.resetLink) {
      return (code: existing, isNew: false);
    }

    final result = await invites.createInvite(
      maxUses: null,
      expiresInSeconds: null,
      // The listing's server, which is not necessarily the one on screen.
      serverId: serverId,
    );
    return (code: result.success ? result.inviteCode : null, isNew: true);
  }
}
