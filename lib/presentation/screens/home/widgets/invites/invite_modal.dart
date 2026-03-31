import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/user_permissions.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../theme/custom_colors.dart';
import 'widgets/copyable_field.dart';
import 'widgets/field_label.dart';
import 'widgets/permission_toggle.dart';

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

  // Permission toggles for the new token
  bool _grantServerAdmin = false;
  bool _grantChannelManager = false;
  bool _grantCanCreateTokens = false;

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
      isServerAdmin: _grantServerAdmin,
      isChannelManager: _grantChannelManager,
      canCreateTokens: _grantCanCreateTokens,
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return BlocBuilder<ServerCubit, ServerState>(
          builder: (context, serverState) {
            final server = serverState.selectedServer;
            final userPerms =
                server?.user?.permissions ?? const UserPermissions();

            final hasAnyGrantable =
                userPerms.isServerAdmin ||
                userPerms.isChannelManager ||
                userPerms.canCreateTokens;

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
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: CustomColors.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.person_add_outlined,
                              size: 18,
                              color: CustomColors.primary,
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
                                  'Generate a one-time access token',
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

                    // Body
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
                            onCopy: () {
                              _copyToClipboard(
                                server?.supabaseUrl ?? '',
                                (v) => setState(() => _copiedUrl = v),
                              );
                            },
                            bgColor: themeState.bgSecondary,
                            borderColor: themeState.borderPrimary,
                            textColor: themeState.textTertiary,
                          ),
                          const SizedBox(height: 14),

                          // Token
                          FieldLabel(
                            label: 'Access Token',
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
                                ? () {
                                    _copyToClipboard(
                                      _inviteToken!,
                                      (v) => setState(() => _copiedToken = v),
                                    );
                                  }
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

                          // Permissions section
                          if (hasAnyGrantable) ...[
                            const SizedBox(height: 16),
                            FieldLabel(
                              label: 'Grant Permissions',
                              textColor: themeState.textTertiary,
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: themeState.bgSecondary,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: themeState.borderPrimary,
                                ),
                              ),
                              child: Column(
                                children: [
                                  if (userPerms.isServerAdmin)
                                    PermissionToggle(
                                      icon: Icons.shield_outlined,
                                      label: 'Server Admin',
                                      description:
                                          'Full server management access',
                                      value: _grantServerAdmin,
                                      onChanged: (v) => setState(() {
                                        _grantServerAdmin = v;
                                        // Admin implies all other permissions
                                        if (v) {
                                          _grantChannelManager = true;
                                          _grantCanCreateTokens = true;
                                        }
                                        _resetToken();
                                      }),
                                      themeState: themeState,
                                      isFirst: true,
                                    ),
                                  if (userPerms.isChannelManager)
                                    PermissionToggle(
                                      icon: Icons.tune_outlined,
                                      label: 'Channel Manager',
                                      description:
                                          'Create channels and moderate members',
                                      value: _grantChannelManager,
                                      // Locked when admin is selected
                                      onChanged: _grantServerAdmin
                                          ? null
                                          : (v) => setState(() {
                                                _grantChannelManager = v;
                                                _resetToken();
                                              }),
                                      themeState: themeState,
                                      isFirst: !userPerms.isServerAdmin,
                                    ),
                                  if (userPerms.canCreateTokens)
                                    PermissionToggle(
                                      icon: Icons.link_outlined,
                                      label: 'Can Invite',
                                      description:
                                          'Allowed to generate invite tokens',
                                      value: _grantCanCreateTokens,
                                      // Locked when admin is selected
                                      onChanged: _grantServerAdmin
                                          ? null
                                          : (v) => setState(() {
                                                _grantCanCreateTokens = v;
                                                _resetToken();
                                              }),
                                      themeState: themeState,
                                      isFirst: !userPerms.isServerAdmin &&
                                          !userPerms.isChannelManager,
                                    ),
                                ],
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

                    // Footer
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

