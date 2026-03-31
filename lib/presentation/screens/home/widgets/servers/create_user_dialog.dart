import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../../logic/cubits/vault/vault_cubit.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/custom_colors.dart';

/// Dialog shown when user is in a server but has no profile yet.
class CreateUserDialog extends StatefulWidget {
  const CreateUserDialog({super.key});

  @override
  State<CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<CreateUserDialog> {
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit =>
      _usernameCtrl.text.trim().isNotEmpty &&
      _displayNameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Derive crypto identity for this server's host
      final server = context.read<ServerCubit>().state.selectedServer;
      if (server == null) {
        setState(() {
          _error = 'No server selected';
          _isLoading = false;
        });
        return;
      }

      final vaultCubit = context.read<VaultCubit>();
      final host = Uri.parse(server.supabaseUrl).host;
      final identity = await vaultCubit.getIdentityForHost(host);

      final result = await context.read<ServerCubit>().createUserAccount(
        username: _usernameCtrl.text.trim(),
        displayName: _displayNameCtrl.text.trim(),
        publicKey: identity.publicKeyBase64,
        stableId: identity.stableId,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _error = result.error;
          _isLoading = false;
        });
        return;
      }

      HelperMethods.showSuccess(message: 'Account created!');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to derive identity: $e';
        _isLoading = false;
      });
    }
  }

  void _dismiss() {
    if (!_isLoading) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: CustomColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.person_outline,
                          size: 20,
                          color: CustomColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Create Your Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: themeState.textPrimary,
                            ),
                          ),
                          Text(
                            'Set up your profile for this server',
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: CustomColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: CustomColors.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: CustomColors.error,
                        ),
                      ),
                    ),
                  ],

                  AppTextField(
                    controller: _usernameCtrl,
                    label: 'Username',
                    hint: 'myusername',
                    enabled: !_isLoading,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    child: Text(
                      'Unique identifier for this server',
                      style: TextStyle(
                        fontSize: 11,
                        color: themeState.textQuaternary,
                      ),
                    ),
                  ),

                  AppTextField(
                    controller: _displayNameCtrl,
                    label: 'Display Name',
                    hint: 'My Display Name',
                    enabled: !_isLoading,
                    onChanged: (_) => setState(() {}),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 20),
                    child: Text(
                      'How others will see you',
                      style: TextStyle(
                        fontSize: 11,
                        color: themeState.textQuaternary,
                      ),
                    ),
                  ),

                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          label: _isLoading ? 'Creating...' : 'Create Account',
                          isLoading: _isLoading,
                          onPressed: _canSubmit && !_isLoading ? _submit : null,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AppButton(
                        label: 'Later',
                        variant: AppButtonVariant.secondary,
                        onPressed: _isLoading ? null : _dismiss,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
