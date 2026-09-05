import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/public_server.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/no_central_account.dart';
import '../../../../common/tag_editor.dart';
import '../../../../theme/app_text.dart';

/// The last step of [AddServerDialog] for anybody who ends up an admin:
/// offering the server to the directory, and describing it.
///
/// Reached two ways, and the second is the one that is easy to miss. Creating
/// a server lands here, obviously. So does *joining* one as its admin — which
/// is how somebody arrives at a server the self-hosted console made for them,
/// a route that skips the create form entirely and so skipped every question
/// on this page. Until it did, those servers had no description, no tags and
/// no listing, and their admin had no idea any of that had been asked of
/// anyone else.
///
/// This is where the choice belongs. Public-or-not is a decision about the
/// server, and the moment you make one is the moment you know the answer —
/// finding it later under a context menu means most servers are private by
/// accident rather than on purpose.
///
/// It is a step *after* registration rather than a section inside the create
/// form, because publishing needs things that do not exist until then: the
/// server's id, and an admin session to mint the listing's invite with. Asking
/// in the form would only have recorded an intention, and an intention that
/// fails — no Rift account, no handle — fails after the dialog has closed,
/// where there is nothing left to say it in.
class PublishNewServerModal extends StatefulWidget {
  /// Ends the whole add-server flow, published or not.
  final VoidCallback onDone;

  const PublishNewServerModal({super.key, required this.onDone});

  @override
  State<PublishNewServerModal> createState() => _PublishNewServerModalState();
}

class _PublishNewServerModalState extends State<PublishNewServerModal> {
  final _descriptionCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();

  /// The tags already turned into chips; a tag still being typed is picked up
  /// at publish time by [ServerTags.withPending].
  List<String> _tags = const [];

  bool _publishing = false;
  String? _error;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;

    setState(() {
      _publishing = true;
      _error = null;
    });

    // The listing's own invite: unlimited uses, no expiry, no permissions.
    final invite = await context.read<ServerCubit>().createInvite(
      maxUses: null,
      expiresInSeconds: null,
      // The server this listing is for, which is also what the publish below
      // names. Same server either way; saying so keeps them from drifting.
      serverId: server.id,
    );
    if (!mounted) return;
    if (!invite.success || invite.inviteCode == null) {
      setState(() {
        _publishing = false;
        _error = invite.error ?? 'Could not create a join link.';
      });
      return;
    }

    final description = _descriptionCtrl.text.trim();
    final cubit = context.read<PublicServersCubit>();
    final saved = await cubit.publish(
      supabaseUrl: server.supabaseUrl,
      serverId: server.id,
      inviteCode: invite.inviteCode!,
      name: server.name,
      description: description.isEmpty ? null : description,
      iconUrl: server.iconUrl,
      tags: ServerTags.withPending(_tags, _tagCtrl.text),
      // Brand new, so its only member is the admin who just registered — the
      // roster fetch for it may not even have landed yet.
      memberCount: 1,
      isListed: true,
    );
    if (!mounted) return;

    if (saved == null) {
      setState(() {
        _publishing = false;
        _error = cubit.state.error;
      });
      return;
    }

    HelperMethods.showSuccess(
      message: '${saved.name} is in the server browser',
    );
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<SupabaseBackupCubit, bool>(
      (c) => c.state.isSignedIn,
    );
    final name = context.select<ServerCubit, String>(
      (c) => c.state.selectedServer?.name ?? 'your server',
    );

    return AppModal(
      title: 'Server created',
      subtitle: signedIn
          ? 'Let people find $name, or keep it invite-only'
          : '$name is ready — it is invite-only',
      maxWidth: K.dialogWidth,
      content: signedIn
          ? _form()
          : const NoCentralAccount(
              need:
                  'The directory lives on the Rift central server, so listing '
                  'a server needs a Rift account. Your server is made and '
                  'works exactly as it should without one — share its invite '
                  'link from the server menu.',
            ),
      actions: [
        AppButton(
          label: signedIn ? 'Keep it private' : 'Done',
          variant: AppButtonVariant.secondary,
          onPressed: _publishing ? null : widget.onDone,
        ),
        if (signedIn)
          AppButton(
            label: 'List publicly',
            isLoading: _publishing,
            onPressed: _publishing ? null : _publish,
          ),
      ],
    );
  }

  Widget _form() {
    final themeState = context.watch<ThemeCubit>().state;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) ...[
          MessageBanner(message: _error!, kind: MessageBannerKind.error),
          const SizedBox(height: 16),
        ],
        Text(
          'A listed server can be found and joined by anyone with a Rift '
          'account, without an invite from you. Either answer can be changed '
          'later, under Discovery in the server settings.',
          style: AppText.secondary.copyWith(color: themeState.textSecondary),
        ),
        const SizedBox(height: 16),
        AppTextField(
          controller: _descriptionCtrl,
          label: 'Description',
          hint: 'What happens here, in a sentence or two',
          enabled: !_publishing,
          maxLines: 3,
          maxLength: PublicServer.maxDescription,
        ),
        const SizedBox(height: 16),
        TagEditor(
          controller: _tagCtrl,
          tags: _tags,
          onChanged: (tags) => setState(() => _tags = tags),
          themeState: themeState,
          enabled: !_publishing,
        ),
        const SizedBox(height: 16),
        const HintCard(
          icon: Icons.public_outlined,
          text:
              'Listing publishes the name, description and tags, this '
              "server's address, its member count and a join link — in the "
              'clear, since a directory has to be readable by strangers. Not '
              'your messages, your members, or any key.',
        ),
      ],
    );
  }
}
