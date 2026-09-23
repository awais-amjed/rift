import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart';
import '../../../../../logic/services/central_handle.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_modal.dart';
import '../../../../common/handle_field.dart';
import '../../../../common/message_banner.dart';

/// Change the handle other people use to find this central account.
///
/// The claim is an upsert, so re-claiming is the same call that made the
/// handle in the first place; only a way to ask for it was missing. Nothing
/// else moves: conversations hang off the account, not the name, so the people
/// already talking to you keep their history and see the new handle.
///
/// What does break is being found by the old one — which is why the warning is
/// on screen before the button rather than in a toast afterwards.
class ChangeHandleDialog extends StatefulWidget {
  final String currentHandle;

  /// Claims [handle], answering with the reason it failed — or null if it
  /// worked. Passed in rather than reached for through the context so this
  /// stays a dialog about a handle, with no opinion about where handles are
  /// kept, and can be exercised without standing up the central stack.
  final Future<String?> Function(String handle) onSubmit;

  const ChangeHandleDialog({
    super.key,
    required this.currentHandle,
    required this.onSubmit,
  });

  @override
  State<ChangeHandleDialog> createState() => _ChangeHandleDialogState();
}

class _ChangeHandleDialogState extends State<ChangeHandleDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentHandle,
  );

  bool _isLoading = false;
  String? _error;

  /// Enabled only for something that would actually change, and could work.
  /// Submitting the handle you already have is a no-op round trip that reads
  /// like a rename, so the button says so by staying dark.
  bool get _canSubmit {
    final next = CentralHandle.normalize(_controller.text);
    return next != widget.currentHandle && CentralHandle.isValid(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final failure = await widget.onSubmit(_controller.text);
    if (!mounted) return;

    if (failure != null) {
      setState(() {
        _error = failure;
        _isLoading = false;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Change handle',
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HandleField(
            controller: _controller,
            enabled: !_isLoading,
            autofocus: true,
            // Editing retracts the last refusal: it described the handle
            // that was submitted, not the one being typed now.
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 12),
          MessageBanner(
            message:
                'Anyone searching for @${widget.currentHandle} will stop '
                'finding you. Conversations you already have are unaffected.',
            kind: MessageBannerKind.caution,
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: _isLoading ? 'Changing...' : 'Change handle',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}

/// Opens [ChangeHandleDialog] for the signed-in central account.
///
/// The claim is an upsert, so re-claiming is the same call that made the
/// handle; the dialog only has to ask for one and report what came back.
void showChangeHandle(BuildContext context, String handle) {
  final cubit = context.read<CentralDmCubit>();
  showDialog<void>(
    context: context,
    builder: (_) => ChangeHandleDialog(
      currentHandle: handle,
      onSubmit: (next) async {
        final ok = await cubit.claimHandle(next);
        // The cubit puts the reason on its own state — a taken handle, a
        // failed request — so take it from there rather than inventing one.
        return ok
            ? null
            : (cubit.state.error ?? 'Could not change your handle.');
      },
    ),
  );
}
