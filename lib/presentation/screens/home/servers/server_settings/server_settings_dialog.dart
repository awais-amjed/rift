import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_limits.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/message_banner.dart';
import '../../../../common/modal_columns.dart';
import 'server_limits_controllers.dart';
import 'widgets/server_connection_section.dart';
import 'widgets/server_limits_section.dart';

/// Admin-only settings for the currently selected server: display name, the
/// LiveKit connection, and the operator limits from migration 007.
///
/// The limits live here rather than anywhere else for the same reason the
/// LiveKit credentials do — saving the attachment cap also has to move the
/// storage bucket's ceiling, which only the service role can do, so it takes
/// the same edge-function trip.
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    _limits.dispose();
    super.dispose();
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

    final livekitUrl = _livekitUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();

    final result = await context.read<ServerCubit>().updateServerDetails(
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

    HelperMethods.showSuccess(message: 'Server settings updated');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return AppModal(
          title: 'Server Settings',
          subtitle: 'Connection and limits for this server',
          // Wide enough for the two halves to stand beside each other. Stacked
          // they ran past the bottom of the window and scrolled, which is a
          // poor trade on a desktop screen with the width to spare —
          // [ModalColumns] falls back to stacking if the window is narrow.
          maxWidth: 760,
          actionsFillWidth: false,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, kind: MessageBannerKind.error),
                const SizedBox(height: 18),
              ],
              ModalColumns(
                children: [
                  ServerConnectionSection(
                    nameCtrl: _nameCtrl,
                    livekitUrlCtrl: _livekitUrlCtrl,
                    apiKeyCtrl: _apiKeyCtrl,
                    secretCtrl: _secretCtrl,
                    themeState: themeState,
                    enabled: !_isLoading,
                  ),
                  ServerLimitsSection(
                    controllers: _limits,
                    themeState: themeState,
                    enabled: !_isLoading,
                  ),
                ],
              ),
            ],
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
      },
    );
  }
}
