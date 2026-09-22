import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../data/constants.dart';
import '../../../../../theme/app_motion.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/theme_context.dart';

/// A central handle, as something to copy.
///
/// It is the only address that person has. There is no directory to look
/// them up in, no server that knows them, and no second way to say who you
/// mean — so the one string that finds them cannot be a subtitle you are
/// unable to select. Mono because it is copied exactly, and with a button
/// because selecting text inside a dialog on a phone is a fight.
///
/// Not [CopyableField]: that one is a full-height field with a worded button
/// beside it, sized to be the *subject* of the invite sheet. Here the handle
/// is one line in a block of facts, and a control that large would read as
/// the point of the profile.
class ProfileHandleRow extends StatefulWidget {
  final String handle;

  const ProfileHandleRow({super.key, required this.handle});

  @override
  State<ProfileHandleRow> createState() => _ProfileHandleRowState();
}

class _ProfileHandleRowState extends State<ProfileHandleRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: '@${widget.handle}'));
    if (!mounted) return;
    setState(() => _copied = true);
    // Said on the button rather than in a toast: the eye is already here,
    // and a toast for a copy is a notification about nothing.
    await Future<void>.delayed(K.copiedHold);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      height: K.controlHeight,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: theme.bgHover,
        borderRadius: BorderRadius.circular(K.radiusRow),
        border: Border.all(color: theme.borderPrimary),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              '@${widget.handle}',
              maxLines: 1,
              style: AppText.code.copyWith(color: theme.textSecondary),
            ),
          ),
          SizedBox.square(
            dimension: 32,
            child: IconButton(
              tooltip: 'Copy handle',
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: _copy,
              icon: AnimatedSwitcher(
                duration: AppMotion.react,
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(_copied),
                  size: 16,
                  color: theme.accentBright,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
