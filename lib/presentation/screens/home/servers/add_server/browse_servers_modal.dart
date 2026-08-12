import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/public_server.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/hint_card.dart';
import '../../../../common/no_central_account.dart';
import 'widgets/browse_results.dart';
import 'widgets/tag_filter_bar.dart';

/// The browse step of [AddServerDialog]: the central directory of servers whose
/// admins chose to be findable.
///
/// Wide, like the create step, because a result is a paragraph and an icon
/// rather than a field — and fixed in height while you search, so the dialog
/// doesn't resize under the cursor between one match and twenty.
class BrowseServersModal extends StatefulWidget {
  final void Function(PublicServer server) onJoin;
  final VoidCallback onCancel;

  const BrowseServersModal({
    super.key,
    required this.onJoin,
    required this.onCancel,
  });

  @override
  State<BrowseServersModal> createState() => _BrowseServersModalState();
}

class _BrowseServersModalState extends State<BrowseServersModal> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (context.read<SupabaseBackupCubit>().state.isSignedIn) {
      context.read<PublicServersCubit>().browse();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Server ids this client already holds. A listing is only an address, so
  /// the check is on the server it points at, not on the listing.
  Set<String> get _joined =>
      context.read<ServerCubit>().state.servers.map((s) => s.id).toSet();

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<SupabaseBackupCubit, bool>(
      (c) => c.state.isSignedIn,
    );

    return AppModal(
      title: 'Browse servers',
      subtitle: 'Public servers you can join without an invite',
      maxWidth: signedIn ? K.dialogWidthWide : K.dialogWidth,
      content: signedIn
          ? _browser()
          : const NoCentralAccount(
              need:
                  'The directory lives on the Rift central server, so finding '
                  'a server in it needs a Rift account.',
            ),
      actions: [
        AppButton(
          label: 'Back',
          variant: AppButtonVariant.secondary,
          onPressed: widget.onCancel,
        ),
      ],
    );
  }

  Widget _browser() {
    return BlocBuilder<PublicServersCubit, PublicServersState>(
      builder: (context, state) {
        final cubit = context.read<PublicServersCubit>();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              controller: _searchCtrl,
              hint: 'Search by name or description',
              autofocus: true,
              onChanged: cubit.search,
            ),
            if (state.visibleTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              TagFilterBar(
                tags: state.visibleTags,
                selected: state.tag,
                onSelected: cubit.toggleTag,
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              height: _resultsHeight,
              child: BrowseResults(
                state: state,
                joinedServerIds: _joined,
                onJoin: widget.onJoin,
                onRetry: cubit.browse,
              ),
            ),
            const SizedBox(height: 12),
            const HintCard(
              text:
                  'Anyone can list a server here, and Rift checks none of it. '
                  'The address under each name is the one thing that cannot be '
                  'made up — you are joining that host, and its admin will see '
                  'you the same way any invited member is seen.',
            ),
          ],
        );
      },
    );
  }

  /// Fixed rather than sized to the results: a list that grows and shrinks as
  /// you type moves the buttons under the cursor.
  static const _resultsHeight = 340.0;
}
