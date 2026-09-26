import 'package:flutter/material.dart';

import '../../../../data/classes/api_response.dart';
import '../../../../data/enums/report_reason.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_dropdown.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/field_label.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';

/// Sends the report; answers what central said.
typedef ReportSender =
    Future<APIResponse> Function(ReportReason reason, String? details);

/// Report a server or bot listing to Rift's moderators.
///
/// A reason from a short list and optional words. The list is what lets the
/// moderator see how bad a thing is claimed to be before reading anything;
/// the words are for what the list cannot say.
class ReportListingDialog extends StatefulWidget {
  /// The listing's name, so the dialog says which one it is about.
  final String name;
  final ReportSender onSend;

  const ReportListingDialog({
    super.key,
    required this.name,
    required this.onSend,
  });

  /// Mirrors `directory_reports.details`, so the field stops where central
  /// would refuse.
  static const maxDetails = 500;

  @override
  State<ReportListingDialog> createState() => _ReportListingDialogState();
}

class _ReportListingDialogState extends State<ReportListingDialog> {
  final _details = TextEditingController();
  ReportReason? _reason;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final details = _details.text.trim();
    final response = await widget.onSend(
      reason,
      details.isEmpty ? null : details,
    );
    if (!mounted) return;
    if (!response.success) {
      setState(() {
        _sending = false;
        _error = response.error;
      });
      return;
    }
    Navigator.of(context).pop();
    HelperMethods.showSuccess(
      message: 'Report sent. Rift moderators will take a look.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppModal(
      title: 'Report ${widget.name}',
      subtitle: 'Tell Rift moderators what is wrong with this listing',
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FieldLabel(label: 'Reason', textColor: theme.textTertiary),
          const SizedBox(height: 8),
          AppDropdown<ReportReason?>(
            value: _reason,
            hint: 'Choose a reason',
            options: [
              for (final reason in ReportReason.values)
                AppDropdownOption(value: reason, label: reason.label),
            ],
            onChanged: _sending ? null : (r) => setState(() => _reason = r),
          ),
          const SizedBox(height: 16),
          AppTextField(
            controller: _details,
            label: 'Anything else (optional)',
            hint: 'What should a moderator look at?',
            maxLines: 4,
            maxLength: ReportListingDialog.maxDetails,
            enabled: !_sending,
          ),
          const SizedBox(height: 8),
          // Said before sending, because it is the thing a reporter would
          // want to know and could not otherwise find out.
          Text(
            'The listing\'s owner is not told who reported it. Moderators '
            'see your handle.',
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
