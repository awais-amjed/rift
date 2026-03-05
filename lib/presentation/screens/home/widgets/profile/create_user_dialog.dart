import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_user.dart';
import '../../../../../data/repositories/server_repository.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
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
  final _repository = ServerRepository();
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

    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final joinResponse = await _repository.joinServer(
      server.supabaseUrl,
      server.token,
      username: _usernameCtrl.text.trim(),
      displayName: _displayNameCtrl.text.trim(),
    );

    if (!mounted) return;

    if (!joinResponse.success) {
      setState(() {
        _error = joinResponse.error;
        _isLoading = false;
      });
      return;
    }

    // Fetch refreshed server details
    final detailsResponse = await _repository.getServerDetails(
      server.supabaseUrl,
      server.token,
    );

    if (!mounted) return;

    if (detailsResponse.success) {
      final rawUser = detailsResponse.data['user'];
      if (rawUser != null) {
        context.read<ServerCubit>().updateServer(
          server.id,
          user: ServerUser.fromJson(rawUser as Map<String, dynamic>),
        );
      }
    }

    HelperMethods.showSuccess(message: 'Account created!');
    Navigator.of(context).pop();
  }

  void _dismiss() {
    if (!_isLoading) Navigator.of(context).pop();
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
