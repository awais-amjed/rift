import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_limits.dart';
import '../../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../server_settings/listing_actions.dart';
import '../../server_settings/listing_draft.dart';
import '../../server_settings/push_toggle.dart';
import '../../server_settings/server_limits_controllers.dart';
import '../../server_settings/server_settings_save.dart';
import '../../server_settings/widgets/server_settings_form.dart';
import '../widgets/manage_panel.dart';

/// The overview page of the manage-server dialog: display name, the LiveKit
/// connection, the operator limits from `002_limits.sql`, and whether the server
/// is in the central directory.
///
/// Takes the server rather than reading the selection, because the dialog
/// opens from the rail's menu for any server — including one you are not
/// looking at. Every write below names it.
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
class OverviewPanel extends StatefulWidget {
  final Server server;

  const OverviewPanel({super.key, required this.server});

  @override
  State<OverviewPanel> createState() => _OverviewPanelState();
}

class _OverviewPanelState extends State<OverviewPanel> {
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

  /// Whether this server may wake its members' phones. Null until the server
  /// has been asked — the toggle is inert rather than lying about being off.
  bool? _pushEnabled;

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
    _loadPushStatus();
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
  ///
  /// Counted by the database rather than by measuring a fetched list. The list
  /// is a page now, so its length is how far we read; and even before it was,
  /// PostgREST capped the response at 1000 rows, so a big server quietly
  /// advertised itself as having exactly a thousand members.
  Future<void> _loadMemberCount() async {
    final counts = await context.read<ServerCubit>().memberCounts(
      serverId: widget.server.id,
    );
    if (!mounted) return;
    setState(() => _memberCount = counts.people + counts.bots);
  }

  /// Also non-blocking, for the same reason as the two above.
  Future<void> _loadPushStatus() async {
    final enabled = await PushToggle.status(
      context.read<ServerCubit>(),
      widget.server.id,
    );
    if (!mounted || enabled == null) return;
    setState(() => _pushEnabled = enabled);
  }

  Future<void> _setPush(bool enabled) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final error = await PushToggle.set(
      context.read<ServerCubit>(),
      widget.server.id,
      enabled: enabled,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _error = error;
      if (error == null) _pushEnabled = enabled;
    });
    if (error == null) {
      HelperMethods.showSuccess(
        message: enabled
            ? 'Push notifications are on for this server'
            : 'Push notifications are off for this server',
      );
    }
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

    // The page stays up: the secret fields are cleared because the server has
    // them now and a form that kept showing a secret is a form that pastes it
    // again on the next Save.
    _apiKeyCtrl.clear();
    _secretCtrl.clear();
    setState(() => _isLoading = false);
    HelperMethods.showSuccess(message: 'Server settings updated');
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
    return ManagePanel(
      title: 'Overview',
      subtitle: 'Connection, limits and discovery',
      footer: [
        AppButton(
          label: 'Save',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
      child: ServerSettingsForm(
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
        pushEnabled: _pushEnabled,
        onPushChanged: _setPush,
      ),
    );
  }
}
