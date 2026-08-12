import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/confirm_dialog.dart';
import 'listing_draft.dart';
import 'widgets/listing_form.dart';
import 'widgets/no_central_account.dart';

/// Publishing the selected server to the central directory — the admin end of
/// the server browser (schema.md, `public_servers`).
///
/// It is its own dialog rather than a third column in Server Settings because
/// it writes to a different database under a different account: everything in
/// Server Settings goes to the server's own project through `update_server`,
/// and everything here goes to central under the user's Rift account. One Save
/// spanning both would have two ways to half-succeed.
class PublicListingDialog extends StatefulWidget {
  const PublicListingDialog({super.key});

  @override
  State<PublicListingDialog> createState() => _PublicListingDialogState();
}

class _PublicListingDialogState extends State<PublicListingDialog> {
  final _draft = ListingDraft();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final server = context.read<ServerCubit>().state.selectedServer;
    final cubit = context.read<PublicServersCubit>();
    await cubit.loadMine();
    if (!mounted || server == null) return;

    setState(() {
      _draft.seed(
        server: server,
        listing: cubit.listingFor(server.supabaseUrl, server.id),
      );
      _loading = false;
    });
  }

  /// The invite code the listing will carry: the one it already has, or a
  /// fresh unlimited-use, permissionless invite minted on this server.
  Future<String?> _inviteCode() async {
    final existing = _draft.listing?.inviteCode;
    if (existing != null && !_draft.resetLink) return existing;

    final result = await context.read<ServerCubit>().createInvite(
      maxUses: null,
      expiresInSeconds: null,
    );
    if (result.success) return result.inviteCode;
    if (mounted) setState(() => _error = result.error);
    return null;
  }

  Future<void> _save() async {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;
    if (_draft.name.isEmpty) {
      setState(() => _error = 'A listed server needs a name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final code = await _inviteCode();
    if (!mounted) return;
    if (code == null) {
      setState(() => _saving = false);
      return;
    }

    final cubit = context.read<PublicServersCubit>();
    final saved = await cubit.publish(
      supabaseUrl: server.supabaseUrl,
      serverId: server.id,
      inviteCode: code,
      name: _draft.name,
      description: _draft.description,
      iconUrl: server.iconUrl,
      tags: _draft.tags,
      memberCount:
          context.read<ServerMembersCubit>().state.members?.length ?? 0,
      isListed: _draft.isListed,
    );
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _saving = false;
        _error = cubit.state.error;
      });
      return;
    }

    HelperMethods.showSuccess(
      message: _draft.isListed
          ? '${saved.name} is now in the server browser'
          : 'Listing saved, and hidden from the browser',
    );
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final listing = _draft.listing;
    if (listing == null) return;

    final confirmed = await showConfirmDialog(
      context: context,
      title: 'Remove this listing?',
      message:
          'The server stays exactly as it is — it just stops being findable. '
          'Anyone already holding its join link can still use it until you '
          'revoke that invite on the server itself.',
      confirmLabel: 'Remove',
      icon: Icons.public_off_outlined,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _saving = true);
    final cubit = context.read<PublicServersCubit>();
    final removed = await cubit.remove(listing.id);
    if (!mounted) return;

    if (!removed) {
      setState(() {
        _saving = false;
        _error = cubit.state.error;
      });
      return;
    }
    HelperMethods.showSuccess(message: 'Listing removed');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<SupabaseBackupCubit, bool>(
      (c) => c.state.isSignedIn,
    );

    return AppModal(
      title: 'Public listing',
      subtitle: 'Let people find this server without an invite',
      maxWidth: signedIn ? K.dialogWidthWide : K.dialogWidth,
      content: !signedIn
          ? const NoCentralAccount()
          : _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : ListingForm(
              draft: _draft,
              error: _error,
              enabled: !_saving,
              onChanged: () => setState(() {}),
              onRemove: _remove,
            ),
      actions: [
        AppButton(
          label: signedIn ? 'Cancel' : 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        if (signedIn)
          AppButton(
            label: 'Save',
            isLoading: _saving,
            onPressed: _saving || _loading ? null : _save,
          ),
      ],
    );
  }
}
