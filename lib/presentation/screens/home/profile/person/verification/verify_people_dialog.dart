import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/constants.dart';
import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../common/app_modal.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/user_avatar.dart';
import '../../../../../theme/app_text.dart';
import '../../../../../theme/custom_colors.dart';
import '../../../../../theme/theme_context.dart';
import 'show_verification.dart';

/// One person a surface can offer to check.
class VerifiablePerson {
  final String id;
  final String name;
  final String? avatarPath;

  /// The key their messages are sealed to. Null for somebody who has never
  /// opened the app, and the row says so instead of offering a code.
  final String? chatKey;

  const VerifiablePerson({
    required this.id,
    required this.name,
    this.avatarPath,
    this.chatKey,
  });
}

/// Who is on the other end of an encrypted surface, and whether their keys
/// have been checked.
///
/// A channel and a call have more than one other person in them, so the
/// encryption chip cannot open one code the way a DM's can. It opens this,
/// and every row leads to the same safety code the profile shows.
class VerifyPeopleDialog extends StatelessWidget {
  /// What this surface is — `#general`, or the voice channel's name.
  final String subtitle;

  /// The claim being made, in the surface's own terms.
  final String explanation;

  final List<VerifiablePerson> people;

  /// `server` or `central`, and what a code needs of this device.
  final String tier;
  final String myId;
  final String host;

  const VerifyPeopleDialog({
    super.key,
    required this.subtitle,
    required this.explanation,
    required this.people,
    required this.tier,
    required this.myId,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    return AppModal(
      title: 'Encryption',
      subtitle: subtitle,
      titleIcon: const Icon(Icons.lock_outline, size: K.iconLarge),
      maxWidth: K.dialogWidth,
      sheetOnPhone: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            explanation,
            style: AppText.body.copyWith(color: theme.textSecondary),
          ),
          const SizedBox(height: 16),
          Text(
            'PEOPLE HERE',
            style: AppText.sectionLabel.copyWith(color: theme.textTertiary),
          ),
          const SizedBox(height: 8),
          if (people.isEmpty)
            const HintCard(
              icon: Icons.person_outline_rounded,
              text: 'Nobody else is here to check right now.',
            )
          else
            for (final person in people)
              _PersonRow(person: person, tier: tier, myId: myId, host: host),
        ],
      ),
    );
  }
}

/// One person, their standing, and the way to the code.
class _PersonRow extends StatelessWidget {
  final VerifiablePerson person;
  final String tier;
  final String myId;
  final String host;

  const _PersonRow({
    required this.person,
    required this.tier,
    required this.myId,
    required this.host,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final code = context.select<AppCubit, String?>(
      (c) => c.state.verifiedCodes['$tier:${person.id}'],
    );
    final hasKey = person.chatKey != null;
    // Whether the stored code still describes their key is the dialog's
    // business, not this row's: the row would have to compute the code for
    // everybody present to know, and that is the work the code exists to
    // make expensive. The row says what was recorded; opening it re-checks.
    final (icon, colour, line) = switch ((hasKey, code != null)) {
      (false, _) => (
        Icons.lock_open_rounded,
        theme.textQuaternary,
        'No key yet',
      ),
      (_, true) => (
        Icons.verified_user_rounded,
        CustomColors.success,
        'Verified',
      ),
      _ => (Icons.shield_outlined, theme.textTertiary, 'Not verified'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(K.radiusRow),
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          borderRadius: BorderRadius.circular(K.radiusRow),
          onTap: hasKey
              ? () => showSafetyCodeFor(
                  context,
                  personName: person.name,
                  tier: tier,
                  theirId: person.id,
                  theirChatKey: person.chatKey,
                  myId: myId,
                  host: host,
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              spacing: 10,
              children: [
                UserAvatar(
                  avatarPath: person.avatarPath,
                  name: person.name,
                  seed: person.id,
                  size: 28,
                ),
                Expanded(
                  child: Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.row.copyWith(color: theme.textPrimary),
                  ),
                ),
                Icon(icon, size: K.iconInline, color: theme.statusInk(colour)),
                Text(
                  line,
                  style: AppText.secondary.copyWith(
                    color: theme.statusInk(colour),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
