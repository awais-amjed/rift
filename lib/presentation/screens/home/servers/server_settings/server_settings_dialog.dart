import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../data/classes/server_limits.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import 'listing_actions.dart';
import 'listing_draft.dart';
import 'server_limits_controllers.dart';
import 'server_settings_save.dart';
import 'widgets/server_settings_form.dart';

/// Admin-only settings for [server]: display name, the LiveKit connection, the
/// operator limits from migration 007, and whether the server is in the central
/// directory.
///
/// Takes the server rather than reading the selection, because it opens from the
/// rail's menu for any server — including one you are not looking at. Every
/// write below names it.
///
/// The limits live here rather than anywhere else for the same reason the
/// LiveKit credentials do — saving the attachment cap also has to move the
/// storage bucket's ceiling, which only the service role can do, so it takes
/// the same edge-function trip.
///
/// Discovery is here because **this is where people look for it**, which turns
/// out to matter more than the fact that it writes somewhere else. It had its
/// own dialog first, on the reasoning that one Save spanning two databases has
/// two ways to half-succeed — true, but that is a problem to solve rather than
/// a reason to hide a setting from the screen it belongs on. Save runs the
/// server's update first and the listing second ([ListingActions]), and says
/// which half landed rather than pretending it is one write.
class ServerSettingsDialog extends StatefulWidget {
  final Server server;

  const ServerSettingsDialog({super.key, required this.server});

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _livekitUrlCtrl;
  final _apiKeyCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _limits = ServerLimitsControllers();
  final _listing = ListingDraft();

  /// What the server reported when the dialog opened, so an unchanged form
  /// doesn't send a write.
  late final ServerLimits _initialLimits;

  /// How many members this server has, for the disclosure the listing makes.
  ///
  /// Fetched here rather than taken from `ServerMembersCubit`, which is the
  /// *selected* server's live roster — and this dialog is not always about the
  /// selected server. Null until it arrives, or if it doesn't.
  int? _memberCount;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _nameCtrl = TextEditingController(text: server.name);
    _livekitUrlCtrl = TextEditingController(text: server.livekitUrl ?? '');
    _initialLimits = server.limits;
    _limits.seed(_initialLimits);
    _loadListing();
    _loadMemberCount();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    _limits.dispose();
    _listing.dispose();
    super.dispose();
  }

  /// The rest of the dialog is usable while this is in flight — it describes a
  /// different database, and a slow central shouldn't hold up a LiveKit URL.
  Future<void> _loadListing() async {
    if (!context.read<SupabaseBackupCubit>().state.isSignedIn) return;
    final server = widget.server;
    final cubit = context.read<PublicServersCubit>();
    await cubit.loadMine();
    if (!mounted) return;

    setState(
      () => _listing.seed(cubit.listingFor(server.supabaseUrl, server.id)),
    );
  }

  /// Also non-blocking, and allowed to fail: the count is a sentence in the
  /// disclosure, not something Save depends on.
  Future<void> _loadMemberCount() async {
    final result = await context.read<ServerCubit>().listMembers(
      serverId: widget.server.id,
    );
    if (!mounted || result.members == null) return;
    setState(() => _memberCount = result.members!.length);
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Server name cannot be empty');
      return;
    }

    final parsed = _limits.read();
    if (parsed.limits == null) {
      setState(() => _error = parsed.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final error = await ServerSettingsSave.run(
      server: widget.server,
      name: name,
      limits: parsed.limits == _initialLimits ? null : parsed.limits,
      livekitUrl: _livekitUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      secret: _secretCtrl.text.trim(),
      draft: _listing,
      serverCubit: context.read<ServerCubit>(),
      publicServers: context.read<PublicServersCubit>(),
      // Whatever the listing already says, if this server's roster never
      // arrived — better a stale count than publishing zero over a real one.
      memberCount: _memberCount ?? _listing.listing?.memberCount ?? 0,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _error = error;
        _isLoading = false;
      });
      return;
    }

    HelperMethods.showSuccess(message: 'Server settings updated');
    Navigator.of(context).pop();
  }

  Future<void> _removeListing() async {
    setState(() => _isLoading = true);
    final result = await ListingActions.remove(
      context,
      draft: _listing,
      publicServers: context.read<PublicServersCubit>(),
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _error = result.error;
    });
    if (result.removed) HelperMethods.showSuccess(message: 'Listing removed');
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Server Settings',
      // Named, because this dialog opens for any server in the rail — not only
      // the one whose channels are on screen behind it.
      subtitle: 'Connection, limits and discovery for ${widget.server.name}',
      maxWidth: K.dialogWidthWidest,
      content: ServerSettingsForm(
        nameCtrl: _nameCtrl,
        livekitUrlCtrl: _livekitUrlCtrl,
        apiKeyCtrl: _apiKeyCtrl,
        secretCtrl: _secretCtrl,
        limits: _limits,
        listing: _listing,
        memberCount: _memberCount,
        error: _error,
        enabled: !_isLoading,
        onChanged: () => setState(() {}),
        onRemoveListing: _removeListing,
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Save',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
    );
  }
}
