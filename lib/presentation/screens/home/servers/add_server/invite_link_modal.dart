import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/resolved_invite.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/message_banner.dart';

/// The first of the two join steps: the link, and nothing else.
///
/// It used to share a form with the username and display name, which meant a
/// bad link was only discovered after both had been typed — and the refusal
/// landed under three fields with no way of saying which one it was about.
/// Now the link is put to the server on its own, and the next step opens
/// already knowing which server it is for.
class InviteLinkModal extends StatefulWidget {
  /// A link that arrived from outside the app — a tapped invite. Resolved on
  /// open rather than shown in the field: somebody who tapped a link has
  /// already handed it over, and asking them to press Continue is asking them
  /// to do it again.
  final String? initialLink;

  final void Function(ResolvedInvite invite) onResolved;
  final VoidCallback onCancel;

  const InviteLinkModal({
    super.key,
    this.initialLink,
    required this.onResolved,
    required this.onCancel,
  });

  @override
  State<InviteLinkModal> createState() => _InviteLinkModalState();
}

class _InviteLinkModalState extends State<InviteLinkModal> {
  late final TextEditingController _linkCtrl = TextEditingController(
    text: widget.initialLink ?? '',
  );

  bool _isLoading = false;
  String? _error;

  bool get _canSubmit => _linkCtrl.text.trim().isNotEmpty && !_isLoading;

  @override
  void initState() {
    super.initState();
    if (widget.initialLink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
    }
  }

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await context.read<ServerCubit>().resolveInvite(
      _linkCtrl.text,
    );
    if (!mounted) return;

    final invite = result.invite;
    if (invite == null) {
      setState(() {
        _isLoading = false;
        _error = result.error;
      });
      return;
    }
    setState(() => _isLoading = false);
    widget.onResolved(invite);
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Join server',
      subtitle: 'Paste the invite link you were given',
      maxWidth: K.dialogWidth,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
            controller: _linkCtrl,
            label: 'Invite link',
            hint: 'https://…#code',
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onEditingComplete: _canSubmit ? _submit : null,
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Back',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : widget.onCancel,
        ),
        AppButton(
          label: _isLoading ? 'Checking…' : 'Continue',
          isLoading: _isLoading,
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }
}
