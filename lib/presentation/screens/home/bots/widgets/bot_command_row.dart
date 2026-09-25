import 'package:flutter/material.dart';

import '../../../../../data/classes/bot_manifest.dart';
import '../../../../../data/constants.dart';
import '../../../../common/app_text_field.dart';
import '../../../../theme/theme_context.dart';

/// The controllers behind one row of [BotManifestEditor].
///
/// A bundle rather than three parallel lists, so a row keeps its own cursor
/// and its own text while its neighbours are added and removed around it.
class BotCommandFields {
  final TextEditingController name;
  final TextEditingController usage;
  final TextEditingController description;

  /// Carried through the editor untouched: whether a command summons the bot
  /// into a call is a claim about what the *bot* does when it sees the verb,
  /// and this form has no way to ask that question usefully.
  final bool summonsBot;
  final bool dismissesBot;

  BotCommandFields({
    required this.name,
    required this.usage,
    required this.description,
    this.summonsBot = false,
    this.dismissesBot = false,
  });

  factory BotCommandFields.empty() => BotCommandFields(
    name: TextEditingController(),
    usage: TextEditingController(),
    description: TextEditingController(),
  );

  factory BotCommandFields.of(BotCommandSpec spec) => BotCommandFields(
    name: TextEditingController(text: spec.name),
    usage: TextEditingController(text: spec.usage),
    description: TextEditingController(text: spec.description),
    summonsBot: spec.summonsBot,
    dismissesBot: spec.dismissesBot,
  );

  /// Null for a row with no verb in it — an empty row is one somebody added
  /// and has not filled in, not a command called "".
  BotCommandSpec? toSpec() {
    final verb = name.text.trim().toLowerCase();
    if (verb.isEmpty) return null;
    final args = usage.text.trim();
    final what = description.text.trim();
    return BotCommandSpec(
      name: verb,
      usage: args.isEmpty ? null : args,
      description: what.isEmpty ? null : what,
      summonsBot: summonsBot,
      dismissesBot: dismissesBot,
    );
  }

  void dispose() {
    name.dispose();
    usage.dispose();
    description.dispose();
  }
}

/// One command: the verb, what it takes, and what it is for.
class BotCommandRow extends StatelessWidget {
  final BotCommandFields fields;
  final bool enabled;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const BotCommandRow({
    super.key,
    required this.fields,
    required this.enabled,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.bgTertiary,
        borderRadius: BorderRadius.circular(K.radiusCard),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: AppTextField(
                  controller: fields.name,
                  hint: 'play',
                  enabled: enabled,
                  maxLength: 32,
                  onChanged: (_) => onChanged(),
                ),
              ),
              Expanded(
                child: AppTextField(
                  controller: fields.usage,
                  hint: '<song>',
                  enabled: enabled,
                  maxLength: 64,
                  onChanged: (_) => onChanged(),
                ),
              ),
              IconButton(
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close_rounded, size: K.iconRow),
                color: theme.textTertiary,
                tooltip: 'Remove',
              ),
            ],
          ),
          AppTextField(
            controller: fields.description,
            hint: 'What it does',
            enabled: enabled,
            maxLength: 120,
            onChanged: (_) => onChanged(),
          ),
        ],
      ),
    );
  }
}
