import 'package:flutter/material.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_text_field.dart';
import '../../../../common/user_avatar.dart';
import '../../../../theme/app_text.dart';

/// Who else is in a private channel.
///
/// Bots are absent by design rather than by oversight: a bot is keyed by an
/// admin's explicit grant and nothing else (BOTS.md §6), so offering one here
/// would be a second door into the same room — and `set_channel_members`
/// refuses them anyway.
///
/// The person creating the channel is not listed either. They are always in it,
/// and a checkbox that cannot be unticked is a worse way of saying so than not
/// drawing one.
class ChannelMemberPicker extends StatelessWidget {
  final ThemeState themeState;
  final List<ServerMember> members;
  final Set<String> selected;
  final String query;
  final TextEditingController queryController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onToggle;
  final bool enabled;

  const ChannelMemberPicker({
    super.key,
    required this.themeState,
    required this.members,
    required this.selected,
    required this.query,
    required this.queryController,
    required this.onQueryChanged,
    required this.onToggle,
    this.enabled = true,
  });

  List<ServerMember> get _visible {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return members;
    return members
        .where(
          (m) =>
              m.displayName.toLowerCase().contains(q) ||
              m.username.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTextField(
          controller: queryController,
          label: 'Who can see it',
          hint: 'Search members',
          enabled: enabled,
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: 8),
        Container(
          height: 168,
          decoration: BoxDecoration(
            color: themeState.bgSecondary,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: themeState.borderPrimary),
          ),
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    members.isEmpty ? 'Nobody else here yet' : 'No matches',
                    style: AppText.secondary.copyWith(
                      color: themeState.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _MemberRow(
                    themeState: themeState,
                    member: visible[i],
                    checked: selected.contains(visible[i].id),
                    onTap: enabled ? () => onToggle(visible[i].id) : null,
                  ),
                ),
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final ThemeState themeState;
  final ServerMember member;
  final bool checked;
  final VoidCallback? onTap;

  const _MemberRow({
    required this.themeState,
    required this.member,
    required this.checked,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          spacing: 10,
          children: [
            UserAvatar(
              avatarPath: member.avatarPath,
              name: member.displayName,
              size: 24,
              themeState: themeState,
              seed: member.id,
            ),
            Expanded(
              child: Text(
                member.displayName,
                overflow: TextOverflow.ellipsis,
                style: AppText.row.copyWith(color: themeState.textPrimary),
              ),
            ),
            Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 18,
              color: checked ? themeState.accentBright : themeState.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
