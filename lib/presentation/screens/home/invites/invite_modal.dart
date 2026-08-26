import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../data/invite_link.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import 'widgets/invite_form.dart';
import 'widgets/invite_options.dart';

/// Modal to generate and copy an invite token for [server].
///
/// Takes the server rather than reading the selection: it opens from the rail's
/// menu, which can be a server you are not currently looking at.
class InviteModal extends StatefulWidget {
  final Server server;

  const InviteModal({super.key, required this.server});

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

  /// Whether the link being minted makes a bot. Off by default: the common
  /// case is inviting a person, and a bot invite is the deliberate one.
  bool _isBot = false;

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
      serverId: widget.server.id,
      isBot: _isBot,
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
        final inviteLink = _inviteToken == null
            ? null
            : InviteLink.build(widget.server.supabaseUrl, _inviteToken!);

        return AppModal(
          title: 'Invite to ${widget.server.name}',
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
            isBot: _isBot,
            onIsBotChanged: (value) => setState(() {
              _isBot = value;
              // A link already on screen was minted as the other kind, so it
              // no longer matches what the switch says.
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
  }
}
