import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/classes/poll.dart';
import '../../../../logic/services/poll_ops.dart';
import '../../../screens/settings/widgets/setting_toggle_row.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../app_button.dart';
import '../../app_modal.dart';
import '../../app_text_field.dart';
import '../../chip_selector.dart';
import '../../row_delete_button.dart';

/// Posts the poll; answers whether it went out, so the dialog knows to close.
typedef PollPoster =
    Future<bool> Function(PollBody body, bool multiple, Duration duration);

/// Over the widget budget and one job: the poll form, whose parts are four
/// inputs that only mean something together.
///
/// Ask the channel something: a question, two to ten answers, whether one
/// person may pick several, and how long it stays open.
///
/// The words are sealed like any message. What the server is told is only
/// how many answers there are, whether several may be picked, and when it
/// closes — the rules it enforces.
class CreatePollDialog extends StatefulWidget {
  final PollPoster onPost;

  const CreatePollDialog({super.key, required this.onPost});

  @override
  State<CreatePollDialog> createState() => _CreatePollDialogState();
}

class _CreatePollDialogState extends State<CreatePollDialog> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multiple = false;

  /// The answer field just added by hand, which takes the caret: pressing
  /// "Add answer" is asking to type one.
  TextEditingController? _justAdded;

  /// A day, the middle of the list: long enough for a channel to see it,
  /// short enough that it is still the question when it closes.
  int _duration = PollOps.durations.indexOf(const Duration(days: 1));
  bool _posting = false;

  List<String> get _filled => [
    for (final option in _options)
      if (option.text.trim().isNotEmpty) option.text.trim(),
  ];

  bool get _canPost =>
      _question.text.trim().isNotEmpty &&
      _filled.length >= PollBody.minOptions &&
      !_posting;

  @override
  void dispose() {
    _question.dispose();
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= PollBody.maxOptions) return;
    final added = TextEditingController();
    setState(() {
      _options.add(added);
      _justAdded = added;
    });
  }

  void _removeOption(int index) {
    if (_options.length <= PollBody.minOptions) return;
    setState(() => _options.removeAt(index).dispose());
  }

  Future<void> _post() async {
    if (!_canPost) return;
    setState(() => _posting = true);
    final posted = await widget.onPost(
      PollBody(question: _question.text.trim(), options: _filled),
      _multiple,
      PollOps.durations[_duration],
    );
    if (!mounted) return;
    if (posted) {
      Navigator.of(context).pop();
    } else {
      setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final label = AppText.sectionLabel.copyWith(color: themeState.textTertiary);
    return AppModal(
      title: 'Create poll',
      subtitle: 'Only the people in this channel can read it',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _question,
            label: 'Question',
            hint: 'What should we ask?',
            autofocus: true,
            enabled: !_posting,
            maxLength: PollBody.maxQuestion,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text('ANSWERS', style: label),
          const SizedBox(height: 8),
          for (var i = 0; i < _options.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              spacing: 6,
              children: [
                Expanded(
                  child: AppTextField(
                    // Keyed by the controller, so removing an answer from
                    // the middle takes its own field away rather than the
                    // last one's.
                    key: ObjectKey(_options[i]),
                    controller: _options[i],
                    hint: 'Answer ${i + 1}',
                    autofocus: identical(_options[i], _justAdded),
                    enabled: !_posting,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(PollBody.maxOption),
                    ],
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_options.length > PollBody.minOptions)
                  RowDeleteButton(
                    tooltip: 'Remove answer',
                    onPressed: _posting ? null : () => _removeOption(i),
                  ),
              ],
            ),
          ],
          if (_options.length < PollBody.maxOptions) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Add answer',
              icon: const Icon(Icons.add_rounded),
              variant: AppButtonVariant.secondary,
              onPressed: _posting ? null : _addOption,
            ),
          ],
          const SizedBox(height: 16),
          Text('OPEN FOR', style: label),
          const SizedBox(height: 8),
          ChipSelector(
            options: [
              for (final duration in PollOps.durations)
                PollOps.durationLabel(duration),
            ],
            selectedIndex: _duration,
            onSelected: (i) => setState(() => _duration = i),
          ),
          const SizedBox(height: 16),
          SettingToggleRow(
            title: 'Allow several answers',
            description: 'Each person may pick more than one.',
            value: _multiple,
            onChanged: _posting ? null : (v) => setState(() => _multiple = v),
          ),
          const SizedBox(height: 12),
          // Said once, where the choice is made: the votes are counted by the
          // server, and hiding them from the room is not hiding them from
          // whoever runs it.
          Text(
            'Everyone sees the totals, not who voted for what. Whoever runs '
            'the server can see the votes.',
            style: AppText.meta.copyWith(color: themeState.textTertiary),
          ),
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _posting ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: 'Post poll',
          isLoading: _posting,
          onPressed: _canPost ? _post : null,
        ),
      ],
    );
  }
}

/// Open the poll dialog over [context].
Future<void> showCreatePollDialog(
  BuildContext context, {
  required PollPoster onPost,
}) => showAppModal<void>(
  context: context,
  modal: CreatePollDialog(onPost: onPost),
);
