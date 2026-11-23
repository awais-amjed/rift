import 'package:material_ui/material_ui.dart';

import '../../../../../data/apis/invites_api.dart';
import '../../../../../data/apis/server_api.dart';
import '../../../../../data/classes/server.dart';
import '../../../../../data/repositories/server_icon_repository.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
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
  ///
  /// [iconPath] is the server's icon as this Save left it, which [server],
  /// read when the dialog opened, may not show yet.
  static Future<String?> save({
    required Server server,
    required String name,
    required String? iconPath,
    required ListingDraft draft,
    required ServerApi serverApi,
    required InvitesApi invites,
    required PublicServersCubit publicServers,
    required int memberCount,
  }) async {
    if (!draft.known) {
      // Not signed in to central (nothing to say), or central did not answer
      // when the dialog opened: then a rename may not have reached the
      // listing, and "Saved" alone would say it had.
      return draft.loadError == null
          ? null
          : 'Server settings saved, but the directory could not be reached, '
                'so its listing was not updated. Try again once Discovery '
                'loads.';
    }
    if (!draft.touchesDirectory) return null;

    // Proof that an admin of this server asked for the listing, before
    // anything is minted. Central cannot tell an administrator from any other
    // member, so it redeems this against the server's own domain before
    // writing anything.
    final proof = await serverApi.listingToken();
    if (proof.token == null) {
      return 'Server settings saved, but the public listing did not: '
          '${proof.error ?? 'this server would not confirm it.'}';
    }

    final minted = await _inviteCode(draft, invites);
    final code = minted.code;
    if (code == null) {
      return minted.error ??
          'Server settings saved, but the listing needs a join link and '
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
      iconSourceUrl: ServerIconRepository.publicUrlOf(
        server.supabaseUrl,
        server.id,
        iconPath,
      ),
      // The picture the listing already shows, kept if the copy fails — but
      // only one in this account's own folder, which a takeover's is not.
      keepIconPath: draft.ownedByMe ? draft.listing?.iconPath : null,
      tags: draft.tags,
      memberCount: memberCount,
      isListed: draft.isListed,
    );
    if (saved == null) {
      // A link minted for a listing that did not happen points at nothing and
      // never expires. The one the listing already had is left alone — it is
      // still in use by the row that is still there.
      if (minted.isNew) {
        await invites.revokeInvite(inviteCode: code);
      }
      return 'Server settings saved, but the public listing did not: '
          '${publicServers.state.error ?? 'central could not be reached.'}';
    }
    final replaced = draft.listing?.inviteCode;
    draft.listing = saved;
    draft.savedNeedsAccount = draft.needsAccount;
    draft.resetLink = false;
    draft.ownedElsewhere = false;

    // A reset is a promise that the old link stops working, so it is taken
    // down once the listing carries the new one, and not before: until then
    // the old one is what the directory hands out.
    if (minted.isNew && replaced != null && replaced != code) {
      if (!await invites.revokeInvite(inviteCode: replaced)) {
        return 'The listing has its new join link, but the old one could not '
            'be revoked and still works. Revoke it under Invite people.';
      }
    }
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
  static Future<({String? code, bool isNew, String? error})> _inviteCode(
    ListingDraft draft,
    InvitesApi invites,
  ) async {
    final existing = draft.listing?.inviteCode;
    if (existing != null && !draft.resetLink) {
      if (draft.needsAccount != draft.savedNeedsAccount) {
        final marked = await invites.setNeedsAccount(
          inviteCode: existing,
          needsAccount: draft.needsAccount,
        );
        if (!marked.success) {
          return (
            code: null,
            isNew: false,
            error:
                'Server settings saved, but whether the join link needs a '
                'Rift account did not: ${marked.error}',
          );
        }
      }
      return (code: existing, isNew: false, error: null);
    }

    final result = await invites.createInvite(
      maxUses: null,
      expiresInSeconds: null,
      needsAccount: draft.needsAccount,
    );
    return (
      code: result.success ? result.inviteCode : null,
      isNew: true,
      error: null,
    );
  }
}
