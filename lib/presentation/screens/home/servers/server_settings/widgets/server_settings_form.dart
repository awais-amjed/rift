import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../common/message_banner.dart';
import '../../../../../common/modal_columns.dart';
import '../listing_draft.dart';
import '../server_limits_controllers.dart';
import 'server_connection_section.dart';
import 'server_discovery_section.dart';
import 'server_limits_section.dart';
import 'server_push_section.dart';

/// The three groups of server settings, side by side: what the server connects
/// to, what it will keep, and who can find it.
///
/// They are three columns rather than one long page because a settings form is
/// a handful of independent groups, not a list — stacked they run past the
/// bottom of the window while a desktop screen has the width sitting unused.
/// [ModalColumns] still stacks them if the window is genuinely narrow.
class ServerSettingsForm extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController livekitUrlCtrl;
  final TextEditingController apiKeyCtrl;
  final TextEditingController secretCtrl;
  final ServerLimitsControllers limits;
  final ListingDraft listing;

  /// This server's member count for the discovery disclosure, or null while the
  /// dialog is still fetching it. Passed in rather than read from a cubit: the
  /// live roster belongs to the *selected* server, and this form is not always
  /// about that one.
  final int? memberCount;

  final String? error;
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
    required this.livekitUrlCtrl,
    required this.apiKeyCtrl,
    required this.secretCtrl,
    required this.limits,
    required this.listing,
    required this.memberCount,
    required this.error,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null) ...[
          MessageBanner(message: error!, kind: MessageBannerKind.error),
          const SizedBox(height: 18),
        ],
        ModalColumns(
          children: [
            ServerConnectionSection(
              nameCtrl: nameCtrl,
              livekitUrlCtrl: livekitUrlCtrl,
              apiKeyCtrl: apiKeyCtrl,
              secretCtrl: secretCtrl,

              enabled: enabled,
            ),
            ServerLimitsSection(controllers: limits, enabled: enabled),
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
        ),
      ],
    );
  }
}
