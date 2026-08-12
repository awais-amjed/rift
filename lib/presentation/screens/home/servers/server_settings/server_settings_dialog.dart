import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/server_members/server_members_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import 'listing_actions.dart';
import 'listing_draft.dart';
import 'server_limits_controllers.dart';
import 'widgets/server_settings_form.dart';

/// Admin-only settings for the currently selected server: display name, the
/// LiveKit connection, the operator limits from migration 007, and whether the
/// server is in the central directory.
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
  const ServerSettingsDialog({super.key});

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

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServerCubit>().state.selectedServer;
    _nameCtrl = TextEditingController(text: server?.name ?? '');
    _livekitUrlCtrl = TextEditingController(text: server?.livekitUrl ?? '');
    _initialLimits = server?.limits ?? ServerLimits.defaults;
    _limits.seed(_initialLimits);
    _loadListing();
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
    final server = context.read<ServerCubit>().state.selectedServer;
    final cubit = context.read<PublicServersCubit>();
    await cubit.loadMine();
    if (!mounted || server == null) return;

    setState(
      () => _listing.seed(cubit.listingFor(server.supabaseUrl, server.id)),
    );
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

    final serverCubit = context.read<ServerCubit>();
    final server = serverCubit.state.selectedServer;
    final livekitUrl = _livekitUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();

    final result = await serverCubit.updateServerDetails(
      name: name,
      livekitUrl: livekitUrl.isEmpty ? null : livekitUrl,
      livekitApiKey: apiKey.isEmpty ? null : apiKey,
      livekitSecretKey: secret.isEmpty ? null : secret,
      limits: parsed.limits == _initialLimits ? null : parsed.limits,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    // Second database, second account. It runs after, so a central outage can
    // never cost the server's own settings.
    final listingError = server == null
        ? null
        : await ListingActions.save(
            server: server,
            name: name,
            draft: _listing,
            serverCubit: serverCubit,
            publicServers: context.read<PublicServersCubit>(),
            memberCount:
                context.read<ServerMembersCubit>().state.members?.length ?? 0,
          );

    if (!mounted) return;

    if (listingError != null) {
      setState(() {
        _error = listingError;
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
      subtitle: 'Connection, limits and discovery for this server',
      maxWidth: K.dialogWidthWidest,
      content: ServerSettingsForm(
        nameCtrl: _nameCtrl,
        livekitUrlCtrl: _livekitUrlCtrl,
        apiKeyCtrl: _apiKeyCtrl,
        secretCtrl: _secretCtrl,
        limits: _limits,
        listing: _listing,
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
