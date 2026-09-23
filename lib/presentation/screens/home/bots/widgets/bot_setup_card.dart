import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../data/classes/public_bot.dart';
import '../../../../../data/constants.dart';
import '../../../../common/field_label.dart';
import '../../../../common/hint_card.dart';
import '../../../../theme/app_text.dart';
import '../../../../theme/theme_context.dart';
import '../../invites/widgets/copyable_field.dart';

/// The second step of adding a bot: the invite the server just minted, and
/// what to do with it.
///
/// **It says the quiet part.** Rift cannot install a bot for you — there is
/// no process for a button to talk to, because a bot runs wherever its author
/// runs it. Pretending otherwise would mean central holding a callback for
/// every author and a session on every server that ever added their bot. So
/// this screen hands over one string and points at the source, which is the
/// honest shape of the thing.
class BotSetupCard extends StatefulWidget {
  final PublicBot bot;
  final String inviteLink;

  const BotSetupCard({super.key, required this.bot, required this.inviteLink});

  @override
  State<BotSetupCard> createState() => _BotSetupCardState();
}

class _BotSetupCardState extends State<BotSetupCard> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.inviteLink));
    if (!mounted) return;
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final dataUse = widget.bot.manifest.dataUse;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(label: 'Bot invite', textColor: theme.textTertiary),
        const SizedBox(height: 6),
        CopyableField(value: widget.inviteLink, copied: _copied, onCopy: _copy),
        const SizedBox(height: 14),
        FieldLabel(label: 'Then', textColor: theme.textTertiary),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.bgTertiary,
            borderRadius: BorderRadius.circular(K.radiusCard),
            border: Border.all(color: theme.borderPrimary),
          ),
          child: Text(
            // The SDK's own first-run shape, from its README. Not a command
            // to paste — every bot's entry point is its author's — but the
            // three arguments are the same for all of them, and seeing them
            // is what makes the invite make sense.
            'const session = await BotSession.join({\n'
            "  invite: '<paste above>',\n"
            '  seed,               // 32 random bytes, kept out of the repo\n'
            "  username: '${_slug(widget.bot.name)}',\n"
            '});',
            style: AppText.code.copyWith(color: theme.textSecondary),
          ),
        ),
        const SizedBox(height: 12),
        HintCard(
          icon: Icons.terminal_rounded,
          text:
              'Follow the bot\'s own instructions at ${widget.bot.sourceHost} '
              'for how to start it. The invite is single-use and is spent on '
              'the first run — the bot saves the session it gets back and '
              'never needs another.',
        ),
        if (dataUse != null && dataUse.isNotEmpty) ...[
          const SizedBox(height: 10),
          // Repeated from the listing on purpose. It was a sentence to read
          // while browsing; here it is the last thing before a program joins
          // a server, which is the moment it binds.
          HintCard(icon: Icons.privacy_tip_outlined, text: dataUse),
        ],
      ],
    );
  }

  /// A bot's name as a username it could plausibly take. Cosmetic — the bot's
  /// author picks the real one, and the server refuses a duplicate anyway.
  static String _slug(String name) {
    final slug = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .trim();
    return slug.isEmpty ? 'bot' : slug;
  }
}
