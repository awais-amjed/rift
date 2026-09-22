import 'package:flutter/material.dart';

import '../../../../data/classes/chat_message.dart';
import '../../../../data/constants.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/forwarding/forward_payload.dart';
import '../../../../logic/services/forwarding/forward_service.dart';
import '../../../../logic/services/forwarding/forward_target.dart';
import '../../../../logic/services/message_excerpt.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../app_button.dart';
import '../../app_modal.dart';
import '../../app_text_field.dart';
import '../../hint_card.dart';
import 'forward_target_row.dart';

/// Over the widget budget and one job: pick a destination, add a line, send.
///
/// Pick where a message goes, add a line of your own, send.
///
/// The hint at the bottom is not decoration. What arrives is the words,
/// under the forwarder's name, with nothing saying where they came from —
/// and the moment to be told that is before choosing to send somebody
/// else's sentence on.
class ForwardDialog extends StatefulWidget {
  final ChatMessage message;
  final List<ForwardTarget> targets;

  /// The server the message's attachments live on, or null for central.
  final String? sourceServerId;

  final ForwardService service;

  const ForwardDialog({
    super.key,
    required this.message,
    required this.targets,
    required this.service,
    this.sourceServerId,
  });

  @override
  State<ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<ForwardDialog> {
  final _search = TextEditingController();
  final _note = TextEditingController();
  final _selected = <String>{};
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _note.dispose();
    super.dispose();
  }

  List<ForwardTarget> get _results =>
      ForwardTargetSearch.filter(widget.targets, _search.text);

  Future<void> _send() async {
    final chosen = widget.targets
        .where((t) => _selected.contains(t.id))
        .toList();
    if (chosen.isEmpty) return;

    final payload = ForwardPayload.of(widget.message);
    if (payload == null) return;

    setState(() => _sending = true);
    final note = _note.text.trim();
    final results = await widget.service.forward(
      message: payload,
      targets: chosen,
      sourceServerId: widget.sourceServerId,
      note: note.isEmpty ? null : note,
    );
    if (!mounted) return;

    Navigator.of(context).pop();
    _report(results);
  }

  /// Say what happened per destination, because they fail independently.
  ///
  /// One failure is named; several are counted. A toast listing five server
  /// names is one nobody reads, and the count is the part that decides
  /// whether to try again.
  void _report(List<ForwardResult> results) {
    final failed = results.where((r) => !r.sent).toList();
    if (failed.isEmpty) {
      HelperMethods.showSuccess(
        message: results.length == 1
            ? 'Forwarded to ${results.first.target.label}'
            : 'Forwarded to ${results.length} conversations',
      );
      return;
    }
    if (failed.length == 1) {
      HelperMethods.showError(
        error: '${failed.first.target.label}: ${failed.first.error}',
      );
      return;
    }
    HelperMethods.showError(
      error: 'Could not forward to ${failed.length} of ${results.length}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return AppModal(
      pageOnPhone: true,
      title: 'Forward message',
      subtitle: MessageExcerpt.of(widget.message),
      maxWidth: K.dialogWidth,
      content: _body(),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: count > 1 ? 'Send to $count' : 'Send',
          isLoading: _sending,
          onPressed: _sending || count == 0 ? null : _send,
        ),
      ],
    );
  }

  Widget _body() {
    final theme = context.theme;
    final results = _results;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // No TapToFocus: AppTextField's own decoration is the tap target
        // (AGENTS.md), and wrapping it would add a second one.
        AppTextField(
          controller: _search,
          hint: 'Search channels and people',
          enabled: !_sending,
          autofocus: true,
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: results.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    widget.targets.isEmpty
                        ? 'Nowhere to forward this yet — join a channel or '
                              'start a conversation first.'
                        : 'Nothing matches that.',
                    textAlign: TextAlign.center,
                    style: AppText.rowQuiet.copyWith(color: theme.textTertiary),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final target = results[i];
                    return ForwardTargetRow(
                      target: target,
                      selected: _selected.contains(target.id),
                      onTap: _sending
                          ? () {}
                          : () => setState(
                              () => _selected.contains(target.id)
                                  ? _selected.remove(target.id)
                                  : _selected.add(target.id),
                            ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _note,
          label: 'Add a line (optional)',
          hint: 'Why you are sending this',
          enabled: !_sending,
          maxLines: 2,
          maxLength: 500,
        ),
        const SizedBox(height: 8),
        const HintCard(
          icon: Icons.info_outlined,
          text:
              'A forward is a new message, signed by you. It carries the '
              'words and not where they came from — nothing there names the '
              'conversation, the channel or the person you got it from.',
        ),
      ],
    );
  }
}
