import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../theme/custom_colors.dart';
import 'widgets/chip_selector.dart';
import 'widgets/copyable_field.dart';
import 'widgets/field_label.dart';
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
  bool _copiedToken = false;
  bool _copiedUrl = false;

  // Expiry — default: 7 days (index 2)
  int _expiryIndex = 2;

  // Max uses — default: 1 (index 0)
  int _usesIndex = 0;

  void _resetToken() {
    _inviteToken = null;
    _copiedToken = false;
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

            return Dialog(
              backgroundColor: themeState.bgPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: themeState.borderPrimary),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Header ──────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: themeState.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.person_add_outlined,
                              size: 18,
                              color: themeState.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Invite to ${server?.name ?? 'Server'}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: themeState.textPrimary,
                                  ),
                                ),
                                Text(
                                  _buildSummary(),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: themeState.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: themeState.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: themeState.borderPrimary),

                    // ── Body ────────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Server URL
                          FieldLabel(
                            label: 'Server URL',
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 6),
                          CopyableField(
                            value: server?.supabaseUrl ?? '',
                            copied: _copiedUrl,
                            onCopy: () => _copyToClipboard(
                              server?.supabaseUrl ?? '',
                              (v) => setState(() => _copiedUrl = v),
                            ),
                            bgColor: themeState.bgSecondary,
                            borderColor: themeState.borderPrimary,
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 16),

                          // Expiry picker
                          FieldLabel(
                            label: 'Expires In',
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          ChipSelector(
                            options: inviteExpiryOptions
                                .map((e) => e.label)
                                .toList(),
                            selectedIndex: _expiryIndex,
                            onSelected: (i) => setState(() {
                              _expiryIndex = i;
                              _resetToken();
                            }),
                            themeState: themeState,
                          ),
                          const SizedBox(height: 16),

                          // Max uses picker
                          FieldLabel(
                            label: 'Max Uses',
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 8),
                          ChipSelector(
                            options: inviteUsesOptions
                                .map((e) => e.label)
                                .toList(),
                            selectedIndex: _usesIndex,
                            onSelected: (i) => setState(() {
                              _usesIndex = i;
                              _resetToken();
                            }),
                            themeState: themeState,
                          ),

                          const SizedBox(height: 16),

                          // Invite code output. Invites are plain — members
                          // join with baseline permissions and admins promote
                          // them later from the Members dialog.
                          FieldLabel(
                            label: 'Invite Code',
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 6),
                          CopyableField(
                            value: _inviteToken,
                            placeholder: _isGenerating
                                ? 'Generating...'
                                : 'Click generate to create a token',
                            copied: _copiedToken,
                            onCopy: _inviteToken != null
                                ? () => _copyToClipboard(
                                    _inviteToken!,
                                    (v) => setState(() => _copiedToken = v),
                                  )
                                : null,
                            bgColor: themeState.bgSecondary,
                            borderColor: themeState.borderPrimary,
                            textColor: themeState.textTertiary,
                            placeholderColor: themeState.textQuaternary,
                          ),

                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: CustomColors.error,
                              ),
                            ),
                          ],

                          const SizedBox(height: 10),
                          Text(
                            'Share both the server URL and token with the person you want to invite.',
                            style: TextStyle(
                              fontSize: 11,
                              color: themeState.textQuaternary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // ── Footer ───────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: AppButton(
                              label: 'Close',
                              variant: AppButtonVariant.secondary,
                              onPressed: () => Navigator.of(context).pop(),
                              expanded: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppButton(
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
                              expanded: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
