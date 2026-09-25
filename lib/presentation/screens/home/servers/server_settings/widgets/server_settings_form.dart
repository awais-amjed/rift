import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../common/modal_columns.dart';
import '../listing_draft.dart';
import 'server_discovery_section.dart';
import 'server_identity_section.dart';
import 'server_push_section.dart';

/// The two groups of server settings that say what a server *is*: what it is
/// called, and who can find it. What it is allowed to grow into is the Limits
/// page's, and where its calls are held is the Voice page's.
///
/// Columns rather than one long page because a settings form is a handful of
/// independent groups, not a list — stacked they run past the bottom of the
/// window while a desktop screen has the width sitting unused. [ModalColumns]
/// still stacks them if the window is genuinely narrow.
class ServerSettingsForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final ListingDraft listing;

  /// This server's member count for the discovery disclosure, or null while the
  /// dialog is still fetching it. Passed in rather than read from a cubit: the
  /// live roster belongs to the *selected* server, and this form is not always
  /// about that one.
  final int? memberCount;

  final bool enabled;

  /// The dialog owns the draft, so every discovery edit has to tell it to
  /// rebuild.
  final VoidCallback onChanged;

  final VoidCallback onRemoveListing;

  /// Whether this server may wake its members' phones, or null while the
  /// server is still being asked. Owned by the dialog because it is not part
  /// of Save — the toggle acts immediately, since turning it on has to mint a
  /// credential on central and hand it over, and half of that is not a state
  /// worth keeping in a form.
  final bool? pushEnabled;
  final ValueChanged<bool> onPushChanged;

  const ServerSettingsForm({
    super.key,
    required this.nameCtrl,
    required this.listing,
    required this.memberCount,
    required this.enabled,
    required this.onChanged,
    required this.onRemoveListing,
    required this.pushEnabled,
    required this.onPushChanged,
  });

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<SupabaseBackupCubit, bool>(
      (c) => c.state.isSignedIn,
    );
    // The failure is the page's to show, above this: see ManagePanel.fill.
    return ModalColumns(
      children: [
        // One field in its own column, because the column beside it is
        // the pair of settings that reach central and the rule between
        // them is the honest division: this one is the server's own.
        ServerIdentitySection(nameCtrl: nameCtrl, enabled: enabled),
        // Discovery and notifications share a column because they are the
        // same kind of setting — the two things this server asks central
        // for, and the two an operator can withdraw.
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ServerDiscoverySection(
              draft: listing,
              signedIn: signedIn,
              memberCount: memberCount,
              onChanged: onChanged,
              onRemove: onRemoveListing,

              enabled: enabled,
            ),
            const SizedBox(height: 22),
            ServerPushSection(
              enabled: pushEnabled,
              signedIn: signedIn,
              onChanged: onPushChanged,

              interactive: enabled,
            ),
          ],
        ),
      ],
    );
  }
}
