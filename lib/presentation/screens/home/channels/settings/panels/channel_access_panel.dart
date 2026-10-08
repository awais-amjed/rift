import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../data/apis/members_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/repositories/session_repository.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../../logic/services/member_selection.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import '../../channel_list/widgets/channel_menu_actions.dart';
import '../../widgets/channel_member_picker.dart';

/// Who can see a channel: everyone, or the people seated in it.
///
/// A public channel is one sentence and the button that closes it. A private
/// one is its member list — open to every member of the room, not only its
/// manager, because knowing who else can read what you are about to say is
/// the whole point of the room being private. Only a manager can change the
/// list or open the room back up; the server refuses anyone else.
///
/// The dialog keys this page on [Channel.isPrivate], so closing or opening
/// the room rebuilds it and a newly private channel loads the people it
/// seated.
class ChannelAccessPanel extends StatefulWidget {
  final Channel channel;
  final bool canManage;

  const ChannelAccessPanel({
    super.key,
    required this.channel,
    required this.canManage,
  });

  @override
  State<ChannelAccessPanel> createState() => _ChannelAccessPanelState();
}

class _ChannelAccessPanelState extends State<ChannelAccessPanel> {
  MemberSelection _selection = MemberSelection.empty;

  /// Who was in the channel when the page loaded, so Save can tell a real
  /// change from a tick-and-untick.
  Set<String> _original = {};

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  Channel get _channel => widget.channel;

  /// The one person who is always in it and is not in the list. Removing
  /// yourself is leaving, which is a different act on the channel's menu.
  String? get _me => context.read<ServerCubit>().state.selectedServer?.user?.id;

  bool get _changed => _selection.differsFrom(_original);

  @override
  void initState() {
    super.initState();
    if (_channel.isPrivate) {
      _load();
    } else {
      _isLoading = false;
    }
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    final members = MembersApi(session: context.read<SessionRepository>());
    final me = _me;
    final membership = await cubit.channelMembers(_channel.id);
    if (!mounted) return;

    // Resolved by id rather than picked out of a roster we no longer hold. A
    // member seated here may be anywhere in the alphabet, and the picker has
    // to draw them whether or not a search would have found them.
    final seated = {...membership.memberIds}..remove(me);
    final rows = await members.membersByIds(seated.toList());
    if (!mounted) return;

    setState(() {
      _original = seated;
      _selection = MemberSelection.of(rows);
      _isLoading = false;
    });
  }

  /// People who could be seated here — never bots, never the caller.
  ///
  /// Bots are excluded by `set_channel_members` too; asking the database for
  /// people only is what stops the picker offering a row it would refuse.
  Future<List<ServerMember>> _search(String query) async {
    final me = _me;
    final results = await MembersApi(
      session: context.read<SessionRepository>(),
    ).searchMembers(query: query, bots: false);
    return [
      for (final member in results)
        if (member.id != me) member,
    ];
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    // The caller's own id goes back in, whatever the picker holds. The RPC
    // replaces the membership with exactly what it is handed, and a private
    // channel that loses its last member is deleted.
    final me = _me;
    final result = await context.read<ServerCubit>().setChannelMembers(
      channelId: _channel.id,
      userIds: {?me, ..._selection.ids}.toList(),
    );
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (result.success) {
        _original = _selection.ids.toSet();
      } else {
        _error = result.error;
      }
    });
    if (result.success) HelperMethods.showSuccess(message: 'Members saved');
  }

  /// No busy state of its own: the confirm is modal while it asks, and on
  /// success the dialog rebuilds this page for the channel's new state.
  Future<void> _setPrivate(bool isPrivate) => isPrivate
      ? makeChannelPrivate(context, _channel)
      : openChannelUp(context, _channel);

  @override
  Widget build(BuildContext context) {
    if (!_channel.isPrivate) return _buildPublic();
    return ManagePanel(
      title: 'Access',
      subtitle: 'Private — only the people below can see it',
      error: _error,
      footer: [
        if (widget.canManage) ...[
          AppButton(
            label: _isSaving ? 'Saving...' : 'Save',
            isLoading: _isSaving,
            onPressed: _changed && !_isSaving ? _save : null,
          ),
          AppButton(
            label: 'Open to everyone',
            variant: AppButtonVariant.secondary,
            onPressed: _isSaving ? null : () => _setPrivate(false),
          ),
        ],
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const LoadingBlock(height: 200)
          else ...[
            if (!widget.canManage) ...[
              const HintCard(
                icon: Icons.visibility_outlined,
                text:
                    'You can see who is in here. Changing it is up to '
                    'whoever runs this channel.',
              ),
              const SizedBox(height: 12),
            ],
            ChannelMemberPicker(
              selection: _selection,
              onSearch: _search,
              enabled: widget.canManage && !_isSaving,
              onToggle: (member) =>
                  setState(() => _selection = _selection.toggled(member)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPublic() {
    // Only a public text channel can go unencrypted: a private one's key is
    // its member list, and a call has no messages to save anything on.
    final offersEncryption = widget.canManage && _channel.hasMessages;
    final encrypted = _channel.isEncrypted;
    return ManagePanel(
      title: 'Access',
      subtitle: encrypted
          ? 'Public — everyone on the server can see it'
          : 'Public and not encrypted — the server can read new messages',
      footer: [
        AppButton(label: 'Make private', onPressed: () => _setPrivate(true)),
        if (offersEncryption)
          AppButton(
            label: encrypted ? 'Turn encryption off' : 'Turn encryption on',
            variant: AppButtonVariant.secondary,
            onPressed: () =>
                setChannelEncryption(context, _channel, encrypted: !encrypted),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          const HintCard(
            icon: Icons.lock_outline_rounded,
            text:
                'Make it private to choose who can see it. Everyone here now '
                'stays in, and you pick who to remove.',
          ),
          if (offersEncryption)
            HintCard(
              icon: encrypted
                  ? Icons.lock_open_rounded
                  : Icons.lock_outline_rounded,
              text: encrypted
                  ? 'Turning encryption off is best for big public channels.'
                  : 'Encryption is off. Turning it on is best for anything '
                        'members would not say in public.',
            ),
        ],
      ),
    );
  }
}
