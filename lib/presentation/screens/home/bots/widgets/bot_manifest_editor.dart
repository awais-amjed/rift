import 'package:flutter/material.dart';

import '../../../../../data/classes/bot_manifest.dart';
import '../../../../common/app_button.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/field_label.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import 'bot_command_row.dart';

/// The manifest half of the listing form: the data-use sentence, and the
/// commands the bot answers to.
///
/// **It asks for the same two things a running bot publishes**
/// (`users.manifest`), because that is the point — the browser shows them
/// before a bot is installed, which is the one moment they are still a
/// decision rather than a description. An author fills this in once; the
/// running bot publishes its own copy, and neither is evidence of the other.
///
/// A form rather than a JSON box. Nobody should have to know the wire shape
/// to say that their bot has a `/play`, and a mistyped brace would fail on a
/// CHECK with nothing useful to say.
class BotManifestEditor extends StatefulWidget {
  final BotManifest manifest;
  final ValueChanged<BotManifest> onChanged;
  final bool enabled;

  const BotManifestEditor({
    super.key,
    required this.manifest,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<BotManifestEditor> createState() => _BotManifestEditorState();
}

class _BotManifestEditorState extends State<BotManifestEditor> {
  late final _dataUseCtrl = TextEditingController(
    text: widget.manifest.dataUse,
  );

  /// One pair of controllers per command row, so a row keeps its cursor while
  /// its neighbours are added and removed.
  late final List<BotCommandFields> _commands = [
    for (final command in widget.manifest.commands)
      BotCommandFields.of(command),
  ];

  /// The column's `length(manifest::text) <= 8192`, spent well before this in
  /// practice — the cap that bites first is having somewhere to put them.
  static const _maxCommands = 25;

  @override
  void dispose() {
    _dataUseCtrl.dispose();
    for (final command in _commands) {
      command.dispose();
    }
    super.dispose();
  }

  void _emit() {
    final dataUse = _dataUseCtrl.text.trim();
    widget.onChanged(
      BotManifest(
        dataUse: dataUse.isEmpty ? null : dataUse,
        commands: [for (final fields in _commands) ?fields.toSpec()],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppTextField(
          controller: _dataUseCtrl,
          label: 'What it does with what it is given',
          hint: 'Messages sent to this bot are forwarded to an outside service',
          enabled: widget.enabled,
          maxLines: 2,
          maxLength: 300,
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 6),
        Text(
          // BOTS.md §8. For a bot that ships text somewhere else, this
          // sentence is worth more than any amount of key management — and
          // it is only worth anything before the bot is installed.
          'Shown above the commands in the bot browser. Leave it empty only if '
          'nothing the bot is told ever leaves the server.',
          style: AppText.label.copyWith(
            fontWeight: FontWeight.w400,
            color: theme.textTertiary,
          ),
        ),
        const SizedBox(height: 16),
        FieldLabel(label: 'Commands', textColor: theme.textTertiary),
        const SizedBox(height: 6),
        for (final (index, fields) in _commands.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BotCommandRow(
              fields: fields,
              enabled: widget.enabled,
              onChanged: _emit,
              onRemove: () {
                setState(() => _commands.removeAt(index).dispose());
                _emit();
              },
            ),
          ),
        if (_commands.length < _maxCommands)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: _commands.isEmpty ? 'Add a command' : 'Add another',
              variant: AppButtonVariant.secondary,
              icon: const Icon(Icons.add_rounded, size: 16),
              onPressed: widget.enabled
                  ? () =>
                        setState(() => _commands.add(BotCommandFields.empty()))
                  : null,
            ),
          ),
      ],
    );
  }
}
