import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_text_field.dart';
import 'create_user_dialog.dart';
import '../../../common/message_banner.dart';
import '../../../theme/app_text.dart';

/// Form to create a brand new server with Supabase + LiveKit credentials.
class CreateServerForm extends StatefulWidget {
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const CreateServerForm({
    super.key,
    required this.onSuccess,
    required this.onCancel,
  });

  @override
  State<CreateServerForm> createState() => _CreateServerFormState();
}

class _CreateServerFormState extends State<CreateServerForm> {
  final _nameCtrl = TextEditingController();
  final _supabaseUrlCtrl = TextEditingController();
  final _setupSecretCtrl = TextEditingController();
  final _livekitUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _supabaseUrlCtrl.text.trim().isNotEmpty &&
      _setupSecretCtrl.text.trim().isNotEmpty &&
      _livekitUrlCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      _secretKeyCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supabaseUrlCtrl.dispose();
    _setupSecretCtrl.dispose();
    _livekitUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _secretKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final supabaseUrl = _supabaseUrlCtrl.text.trim();

    final response = await context.read<ServerCubit>().createServer(
      supabaseUrl: supabaseUrl,
      serviceKey: _setupSecretCtrl.text.trim(),
      name: _nameCtrl.text.trim(),
      livekitUrl: _livekitUrlCtrl.text.trim(),
      livekitApiKey: _apiKeyCtrl.text.trim(),
      livekitSecretKey: _secretKeyCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!response.success) {
      setState(() {
        _error = response.error;
        _isLoading = false;
      });
      return;
    }

    final inviteCode = response.inviteCode!;

    setState(() => _isLoading = false);

    if (!mounted) return;

    // Register as admin using the single-use invite code generated for us.
    final registered = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CreateUserDialog(supabaseUrl: supabaseUrl, inviteCode: inviteCode),
    );

    if (!mounted) return;

    if (registered == true) {
      HelperMethods.showSuccess(message: 'Server created successfully!');
      widget.onSuccess();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: MessageBanner(
                  message: _error!,
                  kind: MessageBannerKind.error,
                ),
              ),

            AppTextField(
              controller: _nameCtrl,
              label: 'Server Name',
              hint: 'My Server',
              enabled: !_isLoading,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),

            // Supabase section
            _SectionDivider(
              label: 'Supabase Configuration',
              borderColor: themeState.borderPrimary,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _supabaseUrlCtrl,
              label: 'Supabase URL',
              hint: 'https://xxxxx.supabase.co',
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _setupSecretCtrl,
              label: 'Service Role Key',
              hint: 'Your Supabase service_role key',
              obscureText: true,
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 18),

            // LiveKit section
            _SectionDivider(
              label: 'LiveKit Configuration',
              borderColor: themeState.borderPrimary,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _livekitUrlCtrl,
              label: 'LiveKit URL',
              hint: 'wss://xxxxx.livekit.cloud',
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _apiKeyCtrl,
              label: 'LiveKit API Key',
              hint: 'API Key',
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _secretKeyCtrl,
              label: 'LiveKit Secret Key',
              hint: 'Secret Key',
              obscureText: true,
              enabled: !_isLoading,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Back first and sized to its label, the commit filling the rest —
            // reading order should run from the way out to the way on, not the
            // other way round.
            Row(
              spacing: 10,
              children: [
                AppButton(
                  label: 'Back',
                  variant: AppButtonVariant.secondary,
                  height: K.fieldHeight,
                  onPressed: _isLoading ? null : widget.onCancel,
                ),
                Expanded(
                  child: AppButton(
                    label: _isLoading ? 'Creating…' : 'Create server',
                    onPressed: _canSubmit && !_isLoading ? _submit : null,
                    isLoading: _isLoading,
                    expanded: true,
                    height: K.fieldHeight,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  final Color borderColor;

  const _SectionDivider({required this.label, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Row(
          children: [
            Text(
              label.toUpperCase(),
              style: AppText.sectionLabel.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: themeState.textTertiary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: borderColor, height: 1)),
          ],
        );
      },
    );
  }
}
