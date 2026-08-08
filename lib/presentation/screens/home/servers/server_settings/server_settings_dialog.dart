import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';

/// Admin-only settings for the currently selected server: display name and the
/// LiveKit connection (URL + API key + secret). The API key/secret are
/// write-only — never fetched to the client — so their fields start blank and
/// are only sent when filled (blank = keep current). Fixes a misconfigured
/// LiveKit setup without re-creating the server.
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

  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final server = context.read<ServerCubit>().state.selectedServer;
    _nameCtrl = TextEditingController(text: server?.name ?? '');
    _livekitUrlCtrl = TextEditingController(text: server?.livekitUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final livekitUrl = _livekitUrlCtrl.text.trim();
    final apiKey = _apiKeyCtrl.text.trim();
    final secret = _secretCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Server name cannot be empty');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await context.read<ServerCubit>().updateServerDetails(
      name: name,
      livekitUrl: livekitUrl.isEmpty ? null : livekitUrl,
      livekitApiKey: apiKey.isEmpty ? null : apiKey,
      livekitSecretKey: secret.isEmpty ? null : secret,
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
          subtitle: 'Name and LiveKit connection for this server',
          fullPage: true,
          maxWidth: K.dialogContentWidth,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, kind: MessageBannerKind.error),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: _nameCtrl,
                label: 'Server Name',
                hint: 'My Server',
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _livekitUrlCtrl,
                label: 'LiveKit URL',
                hint: 'wss://livekit.example.com',
                enabled: !_isLoading,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _apiKeyCtrl,
                label: 'LiveKit API Key',
                hint: 'Leave blank to keep current',
                enabled: !_isLoading,
                obscureText: true,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _secretCtrl,
                label: 'LiveKit Secret Key',
                hint: 'Leave blank to keep current',
                enabled: !_isLoading,
                obscureText: true,
              ),
              const SizedBox(height: 8),
              Text(
                'The API key and secret are stored only on the server and '
                'never sent back — leave them blank to keep the current '
                'values.',
                style: AppText.label.copyWith(
                  fontSize: 11,
                  color: themeState.textTertiary,
                ),
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
