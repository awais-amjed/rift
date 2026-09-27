import 'package:flutter/material.dart';

import '../../../../data/classes/api_response.dart';
import '../../../../data/enums/member_report_reason.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_dropdown.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/field_label.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// Sends the report; answers what the server said.
typedef MemberReportSender =
    Future<APIResponse> Function(MemberReportReason reason, String? note);

/// Report a message or a member to the people who moderate this server.
///
/// The sibling of the directory's report dialog, with this server's reasons
/// and this server's moderators: a reason from a short list, and optional
/// words for what the list cannot say.
class ReportDialog extends StatefulWidget {
  /// "Report message", "Report Sam".
  final String title;

  /// What the report is about, said under the title.
  final String subtitle;

  /// Said before sending: what moderators will see.
  final String disclosure;
  final MemberReportSender onSend;

  const ReportDialog({
    super.key,
    required this.title,
    required this.subtitle,
    required this.disclosure,
    required this.onSend,
  });

  /// Mirrors the server's ceiling on `reports.note`.
  static const maxNote = 1000;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _note = TextEditingController();
  MemberReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The server's refusals, in words. Anything else is shown as it came.
  static String _describe(APIResponse response) =>
      switch (response.errorCode) {
        'already_reported' => 'You have already reported this.',
        'too_many_reports' =>
          'You have 20 reports waiting for a moderator. Try again once some '
              'have been looked at.',
        'cannot_report_self' => 'You cannot report yourself.',
        'message_not_found' => 'That message is gone.',
        _ => response.error ?? 'Could not send the report.',
      };

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final note = _note.text.trim();
    final response = await widget.onSend(reason, note.isEmpty ? null : note);
    if (!mounted) return;
    if (!response.success) {
      setState(() {
        _sending = false;
        _error = _describe(response);
      });
      return;
    }
    Navigator.of(context).pop();
    HelperMethods.showSuccess(
      message: 'Report sent to this server\'s moderators.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppModal(
      title: widget.title,
      subtitle: widget.subtitle,
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label: 'Reason', textColor: theme.textTertiary),
          const SizedBox(height: 8),
          AppDropdown<MemberReportReason?>(
            value: _reason,
            hint: 'Choose a reason',
            options: [
              for (final reason in MemberReportReason.values)
                AppDropdownOption(value: reason, label: reason.label),
            ],
            onChanged: _sending ? null : (r) => setState(() => _reason = r),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _note,
            label: 'Anything else (optional)',
            hint: 'What should a moderator know?',
            maxLines: 4,
            maxLength: ReportDialog.maxNote,
            enabled: !_sending,
          ),
          const SizedBox(height: 8),
          Text(
            widget.disclosure,
            style: AppText.meta.copyWith(color: theme.textTertiary),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Send report',
          isLoading: _sending,
          onPressed: _reason == null || _sending ? null : _send,
        ),
      ],
    );
  }
}
