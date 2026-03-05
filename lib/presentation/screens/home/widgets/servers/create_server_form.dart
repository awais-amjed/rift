import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/repositories/server_repository.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/custom_colors.dart';

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
  final _repository = ServerRepository();

  final _nameCtrl = TextEditingController();
  final _supabaseUrlCtrl = TextEditingController();
  final _livekitUrlCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _secretKeyCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _supabaseUrlCtrl.text.trim().isNotEmpty &&
      _livekitUrlCtrl.text.trim().isNotEmpty &&
      _apiKeyCtrl.text.trim().isNotEmpty &&
      _secretKeyCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supabaseUrlCtrl.dispose();
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

    final response = await _repository.createServer(
      supabaseUrl,
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

    final serverData = response.data['server'] as Map<String, dynamic>;
    final adminToken = response.data['token'] as String;

    context.read<ServerCubit>().addCreatedServer(supabaseUrl, {
      ...serverData,
      'user': null,
      'channels': <dynamic>[],
    }, adminToken);

    HelperMethods.showSuccess(message: 'Server created successfully!');
    widget.onSuccess();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = context.read<ThemeCubit>().state.borderPrimary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) _ErrorBanner(message: _error!),

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
          borderColor: borderColor,
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _supabaseUrlCtrl,
          label: 'Supabase URL',
          hint: 'https://xxxxx.supabase.co',
          enabled: !_isLoading,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 18),

        // LiveKit section
        _SectionDivider(
          label: 'LiveKit Configuration',
          borderColor: borderColor,
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

        Row(
          children: [
            Expanded(
              child: AppButton(
                label: _isLoading ? 'Creating...' : 'Create Server',
                onPressed: _canSubmit && !_isLoading ? _submit : null,
                isLoading: _isLoading,
                expanded: true,
              ),
            ),
            const SizedBox(width: 10),
            AppButton(
              label: 'Back',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : widget.onCancel,
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionDivider extends StatelessWidget {
  final String label;
  final Color borderColor;

  const _SectionDivider({required this.label, required this.borderColor});

  @override
  Widget build(BuildContext context) {
    final textTertiary = context.read<ThemeCubit>().state.textTertiary;
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: textTertiary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: borderColor, height: 1)),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CustomColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CustomColors.error.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: CustomColors.error),
      ),
    );
  }
}
