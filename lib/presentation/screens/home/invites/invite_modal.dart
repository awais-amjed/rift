import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/invite_link.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import 'widgets/invite_form.dart';
import 'widgets/invite_options.dart';

/// Modal to generate and copy an invite token for a server.
class InviteModal extends StatefulWidget {
  const InviteModal({super.key});

  @override
  State<InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<InviteModal> {
  bool _isGenerating = false;
  String? _inviteToken;
  String? _error;
  bool _copiedLink = false;

  // Expiry — default: 7 days (index 2)
  int _expiryIndex = 2;

  // Max uses — default: 1 (index 0)
  int _usesIndex = 0;

  void _resetToken() {
    _inviteToken = null;
    _copiedLink = false;
    _error = null;
  }

  Future<void> _generate() async {
    setState(() {
      _isGenerating = true;
      _error = null;
      _inviteToken = null;
    });

    final result = await context.read<ServerCubit>().createInvite(
      maxUses: inviteUsesOptions[_usesIndex].value,
      expiresInSeconds: inviteExpiryOptions[_expiryIndex].seconds,
    );

    if (!mounted) return;

    setState(() {
      _isGenerating = false;
      if (result.success) {
        _inviteToken = result.inviteCode;
      } else {
        _error = result.error;
      }
    });
  }

  void _copyToClipboard(String text, void Function(bool) setCopied) async {
    await Clipboard.setData(ClipboardData(text: text));
    setCopied(true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setCopied(false);
  }

  String _buildSummary() {
    final expiry = inviteExpiryOptions[_expiryIndex];
    final uses = inviteUsesOptions[_usesIndex];
    final expiryText = expiry.seconds == null
        ? 'Never expires'
        : 'Expires in ${expiry.label}';
    final usesText = uses.value == null
        ? 'Unlimited uses'
        : '${uses.label} use${uses.value == 1 ? '' : 's'}';
    return '$expiryText · $usesText';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ServerCubit, ServerState>(
          builder: (context, serverState) {
            final server = serverState.selectedServer;
            final inviteLink = (_inviteToken != null && server != null)
                ? InviteLink.build(server.supabaseUrl, _inviteToken!)
                : null;

            return AppModal(
              title: 'Invite to ${server?.name ?? 'Server'}',
              subtitle: _buildSummary(),
              titleIcon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: themeState.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_add_outlined,
                  size: 18,
                  color: themeState.primary,
                ),
              ),
              content: InviteForm(
                themeState: themeState,
                expiryIndex: _expiryIndex,
                usesIndex: _usesIndex,
                onExpirySelected: (i) => setState(() {
                  _expiryIndex = i;
                  _resetToken();
                }),
                onUsesSelected: (i) => setState(() {
                  _usesIndex = i;
                  _resetToken();
                }),
                inviteLink: inviteLink,
                isGenerating: _isGenerating,
                copied: _copiedLink,
                onCopy: inviteLink == null
                    ? null
                    : () => _copyToClipboard(
                        inviteLink,
                        (v) => setState(() => _copiedLink = v),
                      ),
                error: _error,
              ),
              actions: [
                AppButton(
                  label: 'Close',
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                AppButton(
                  label: _isGenerating
                      ? 'Generating...'
                      : _inviteToken != null
                      ? 'Regenerate'
                      : 'Generate',
                  isLoading: _isGenerating,
                  onPressed: _isGenerating ? null : _generate,
                  icon: _isGenerating
                      ? null
                      : const Icon(
                          Icons.person_add_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
