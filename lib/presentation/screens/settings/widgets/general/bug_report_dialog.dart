import 'package:flutter/material.dart';

import '../../../../../data/classes/api_response.dart';
import '../../../../../data/repositories/bug_report_repository.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';

/// Sends the report; answers what central said, and on success how many log
/// files failed to upload.
typedef BugReportSender = Future<APIResponse> Function(String description);

/// Tell the Rift team something went wrong, with the app's logs attached.
///
/// Words only, no category: the person sending it knows what happened, not
/// which part of the app did it, and the logs say the rest.
class BugReportDialog extends StatefulWidget {
  final BugReportSender onSend;

  /// False when there is no Rift account to send it from; the dialog then
  /// says where to sign in instead of offering a send that would fail.
  final bool signedIn;

  const BugReportDialog({
    super.key,
    required this.onSend,
    required this.signedIn,
  });

  @override
  State<BugReportDialog> createState() => _BugReportDialogState();
}

class _BugReportDialogState extends State<BugReportDialog> {
  final _description = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _description.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final response = await widget.onSend(_description.text.trim());
    if (!mounted) return;
    if (!response.success) {
      setState(() {
        _sending = false;
        _error = response.error;
      });
      return;
    }
    Navigator.of(context).pop();
    final failed = response.data as int? ?? 0;
    HelperMethods.showSuccess(
      message: failed == 0
          ? 'Report sent. Thank you!'
          : 'Report sent, but some of the logs did not upload.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final note = AppText.meta.copyWith(color: theme.textTertiary);
    return AppModal(
      title: 'Report a bug',
      subtitle: 'Tell the Rift team what went wrong',
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _description,
            label: 'What happened?',
            hint: 'What were you doing, and what went wrong?',
            maxLines: 6,
            maxLength: BugReportRepository.maxDescription,
            enabled: !_sending && widget.signedIn,
          ),
          const SizedBox(height: 8),
          // Said before sending: what leaves the device is the thing someone
          // would want to know and could not otherwise find out.
          Text(
            widget.signedIn
                ? "This app's logs from its last few sessions go with it: the "
                      'version, your system, errors, and the names of windows '
                      'you shared. Never your messages or keys. The Rift team '
                      'sees your handle.'
                : 'Sign in to your Rift account under Settings → Account & '
                      'backup to send a report.',
            style: note,
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
          onPressed:
              !widget.signedIn || _sending || _description.text.trim().isEmpty
              ? null
              : _send,
        ),
      ],
    );
  }
}
