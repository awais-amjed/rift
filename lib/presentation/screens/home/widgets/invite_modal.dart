import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server.dart';
import '../../../../data/repositories/server_repository.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../theme/custom_colors.dart';

/// Modal to generate and copy an invite token for a server.
class InviteModal extends StatefulWidget {
  const InviteModal({super.key});

  @override
  State<InviteModal> createState() => _InviteModalState();
}

class _InviteModalState extends State<InviteModal> {
  final _repository = ServerRepository();

  bool _isGenerating = false;
  String? _inviteToken;
  String? _error;
  bool _copiedToken = false;
  bool _copiedUrl = false;

  Future<void> _generate() async {
    final server = context.read<ServerCubit>().state.selectedServer;
    if (server == null) return;

    setState(() {
      _isGenerating = true;
      _error = null;
      _inviteToken = null;
    });

    final response = await _repository.createAccessToken(
      server.supabaseUrl,
      server.token,
    );

    if (!mounted) return;

    setState(() => _isGenerating = false);

    if (response.success) {
      setState(() => _inviteToken = response.data['token'] as String);
    } else {
      setState(
        () => _error = response.error ?? 'Failed to generate invite token',
      );
    }
  }

  void _copyToClipboard(String text, void Function(bool) setCopied) async {
    await Clipboard.setData(ClipboardData(text: text));
    setCopied(true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setCopied(false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark
        ? CustomColors.bgPrimaryDark
        : CustomColors.bgPrimaryLight;
    final borderColor = isDark
        ? CustomColors.borderPrimaryDark
        : CustomColors.borderPrimaryLight;
    final textPrimary = isDark
        ? CustomColors.textPrimaryDark
        : CustomColors.textPrimaryLight;
    final textTertiary = isDark
        ? CustomColors.textTertiaryDark
        : CustomColors.textTertiaryLight;
    final textQuaternary = isDark
        ? CustomColors.textQuaternaryDark
        : CustomColors.textQuaternaryLight;
    final bgSecondary = isDark
        ? CustomColors.bgSecondaryDark
        : CustomColors.bgSecondaryLight;

    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, serverState) {
        final server = serverState.selectedServer;

        return Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderColor),
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
                          color: CustomColors.primary.withOpacity(0.1),
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
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              'Generate a one-time access token',
                              style: TextStyle(
                                fontSize: 11,
                                color: textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.close, size: 18, color: textTertiary),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),

                // Body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Server URL
                      _FieldLabel(label: 'Server URL', textColor: textTertiary),
                      const SizedBox(height: 6),
                      _CopyableField(
                        value: server?.supabaseUrl ?? '',
                        copied: _copiedUrl,
                        onCopy: () {
                          _copyToClipboard(
                            server?.supabaseUrl ?? '',
                            (v) => setState(() => _copiedUrl = v),
                          );
                        },
                        bgColor: bgSecondary,
                        borderColor: borderColor,
                        textColor: textTertiary,
                      ),
                      const SizedBox(height: 14),

                      // Token
                      _FieldLabel(
                        label: 'Access Token',
                        textColor: textTertiary,
                      ),
                      const SizedBox(height: 6),
                      _CopyableField(
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
                        bgColor: bgSecondary,
                        borderColor: borderColor,
                        textColor: textTertiary,
                        placeholderColor: textQuaternary,
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
                        style: TextStyle(fontSize: 11, color: textQuaternary),
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
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final Color textColor;

  const _FieldLabel({required this.label, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: textColor,
      ),
    );
  }
}

class _CopyableField extends StatelessWidget {
  final String? value;
  final String? placeholder;
  final bool copied;
  final VoidCallback? onCopy;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final Color? placeholderColor;

  const _CopyableField({
    this.value,
    this.placeholder,
    required this.copied,
    this.onCopy,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    this.placeholderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor = isDark
        ? CustomColors.bgHoverDark
        : CustomColors.bgHoverLight;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: value != null
                ? Text(
                    value!,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: textColor,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                : Text(
                    placeholder ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: placeholderColor ?? textColor,
                    ),
                  ),
          ),
          if (onCopy != null)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                hoverColor: hoverColor,
                onTap: onCopy,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    copied ? Icons.check : Icons.copy,
                    size: 15,
                    color: copied ? CustomColors.success : textColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
