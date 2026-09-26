import 'package:flutter/material.dart';

import '../../../../data/classes/api_response.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// A moderator's action that carries a reason: hiding a listing, banning a
/// publisher. The reason is shown to the person it happens to, so the field
/// says so.
///
/// Runs the action itself and stays open on a refusal, so a moderator reads
/// why in the place they asked rather than in a toast after it closed.
class ModerationReasonDialog extends StatefulWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Future<APIResponse> Function(String? reason) onConfirm;

  const ModerationReasonDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.onConfirm,
  });

  /// Mirrors the 300-character columns the reason is stored in.
  static const maxReason = 300;

  @override
  State<ModerationReasonDialog> createState() => _ModerationReasonDialogState();
}

class _ModerationReasonDialogState extends State<ModerationReasonDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final reason = _reason.text.trim();
    final response = await widget.onConfirm(reason.isEmpty ? null : reason);
    if (!mounted) return;
    if (response.success) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _error = response.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppModal(
      title: widget.title,
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message,
            style: AppText.secondary.copyWith(color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _reason,
            label: 'Reason (shown to the owner)',
            hint: 'For example: breaks the rules on hateful content',
            maxLines: 3,
            maxLength: ModerationReasonDialog.maxReason,
            autofocus: true,
            enabled: !_busy,
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        AppButton(
          label: widget.confirmLabel,
          variant: AppButtonVariant.danger,
          isLoading: _busy,
          onPressed: _busy ? null : _confirm,
        ),
      ],
    );
  }
}
