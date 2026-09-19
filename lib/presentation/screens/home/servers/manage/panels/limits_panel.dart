import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/classes/server.dart';
import '../../../../../../data/classes/server_limits.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/message_banner.dart';
import '../../server_settings/server_limits_controllers.dart';
import '../../server_settings/widgets/server_limits_section.dart';
import '../widgets/manage_panel.dart';

/// Every ceiling an operator may put on a server: how much it keeps, how many
/// people it holds, and what one call may cost.
///
/// Its own page rather than a third of Overview, which is where it started.
/// Overview is what the server *is* — its name, where its voice lives, whether
/// central knows about it — and these are a decision about what it is allowed
/// to grow into. Seven boxes is also simply too much to be the middle column
/// of somewhere else.
///
/// Takes the server rather than reading the selection, because the dialog
/// opens from the rail's menu for any server, including one you are not
/// looking at. The write below names it.
class LimitsPanel extends StatefulWidget {
  final Server server;

  const LimitsPanel({super.key, required this.server});

  @override
  State<LimitsPanel> createState() => _LimitsPanelState();
}

class _LimitsPanelState extends State<LimitsPanel> {
  final _limits = ServerLimitsControllers();

  /// What the server reported when the page opened, so Save on an untouched
  /// form is a no-op rather than a write.
  late final ServerLimits _initial;

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initial = widget.server.limits;
    _limits.seed(_initial);
  }

  @override
  void dispose() {
    _limits.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = _limits.read();
    if (parsed.limits == null) {
      setState(() => _error = parsed.error);
      return;
    }
    if (parsed.limits == _initial) {
      HelperMethods.showSuccess(message: 'Nothing to change');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Only the limits: `update_server` leaves out what it isn't sent, so this
    // cannot disturb the name or the LiveKit credentials that Overview owns.
    final result = await context.read<ServerCubit>().updateServerDetails(
      limits: parsed.limits,
      serverId: widget.server.id,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error ?? 'Failed to save the limits';
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = false);
    HelperMethods.showSuccess(message: 'Limits updated');
  }

  @override
  Widget build(BuildContext context) {
    return ManagePanel(
      title: 'Limits',
      subtitle: 'What this server is allowed to cost',
      footer: [
        AppButton(
          label: 'Save',
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _submit,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error case final error?) ...[
            MessageBanner(message: error, kind: MessageBannerKind.error),
            const SizedBox(height: 18),
          ],
          ServerLimitsSection(
            controllers: _limits,
            enabled: !_isLoading,
            storageUsed: widget.server.storageUsed,
          ),
        ],
      ),
    );
  }
}
