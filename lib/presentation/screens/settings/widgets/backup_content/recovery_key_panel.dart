import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../section_title.dart';

/// Replacing the recovery key.
///
/// There is deliberately no way to *view* the existing one. It is not stored
/// anywhere on the device after it was acknowledged — only the blob it opens
/// is — so a "show my recovery key" button could only ever be a lie or a
/// second copy waiting to leak. Replacing it is the honest operation: it mints
/// a new key, rewraps the seed, and the old key stops working.
class RecoveryKeyPanel extends StatefulWidget {
  const RecoveryKeyPanel({super.key});

  @override
  State<RecoveryKeyPanel> createState() => _RecoveryKeyPanelState();
}

class _RecoveryKeyPanelState extends State<RecoveryKeyPanel> {
  final _password = TextEditingController();
  bool _open = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _replace() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final result = await context.read<SupabaseBackupCubit>().replaceRecoveryKey(
      password: _password.text,
    );

    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    // Nothing to show here: the new key lands in VaultState as pending, and
    // the router insists on the same full-screen hand-over that a new vault
    // gets. One place where a recovery key is ever displayed, not two.
    _password.clear();
    setState(() {
      _busy = false;
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: 'Recovery key'),
        const SizedBox(height: 4),
        Text(
          'The key you were shown when this vault was created. It unlocks your '
          'vault without the password — replace it if you think somebody else '
          'has seen it.',
          style: AppText.secondary.copyWith(
            color: theme.textTertiary,
            height: 1.5,
          ),
        ),

        if (!_open) ...[
          const SizedBox(height: 14),
          AppButton(
            label: 'Replace recovery key',
            variant: AppButtonVariant.secondary,
            onPressed: () => setState(() => _open = true),
          ),
        ] else ...[
          const SizedBox(height: 16),
          AppTextField(
            controller: _password,
            label: 'Password',
            hint: 'Confirm it is you',
            obscureText: true,
            enabled: !_busy,
            autofocus: true,
            onSubmitted: (_) => _busy ? null : _replace(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            MessageBanner(message: _error!, kind: MessageBannerKind.error),
          ],
          const SizedBox(height: 12),
          const MessageBanner(
            message:
                'The old key stops working immediately, including on backups '
                'already saved. You will be shown the new one once.',
            kind: MessageBannerKind.caution,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.secondary,
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _open = false;
                        _error = null;
                        _password.clear();
                      }),
              ),
              const SizedBox(width: 8),
              AppButton(
                label: 'Replace',
                isLoading: _busy,
                onPressed: _busy ? null : _replace,
              ),
            ],
          ),
        ],
      ],
    );
  }
}
