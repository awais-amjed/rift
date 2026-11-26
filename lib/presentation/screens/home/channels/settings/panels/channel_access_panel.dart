import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../data/apis/channel_access_api.dart';
import '../../../../../../data/apis/members_api.dart';
import '../../../../../../data/classes/channel.dart';
import '../../../../../../data/classes/server_member.dart';
import '../../../../../../data/enums/channel_type.dart';
import '../../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../../logic/helper_methods.dart';
import '../../../../../../logic/services/member_selection.dart';
import '../../../../../common/app_button.dart';
import '../../../../../common/hint_card.dart';
import '../../../../../common/loading_block.dart';
import '../../../../../common/server_scope.dart';
import '../../../servers/manage/widgets/manage_panel.dart';
import '../../channel_list/widgets/channel_menu_actions.dart';
import '../../widgets/channel_member_picker.dart';

/// Over the widget budget and one job: who can see a channel, and a private
/// one's member list.
///
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

  /// Who was ticked when the page loaded, so Save can tell a real change from
  /// a tick-and-untick, and send only what changed.
  Set<String> _original = {};

  /// Everybody seated when the page loaded, the caller included, whether or
  /// not their name resolved: what a server from before
  /// `change_channel_members` is handed, less and plus the change.
  Set<String> _seated = {};

  bool _isLoading = true;

  /// The read of who is in here failed. Drawn as that, with no Save: drawn as
  /// nobody ticked, ticking one person and saving removed everybody else.
  bool _loadFailed = false;
  bool _isSaving = false;
  String? _error;

  Channel get _channel => widget.channel;

  /// The one person who is always in it and is not in the list. Removing
  /// yourself is leaving, which is a different act on the channel's menu.
  String? get _me => context
      .read<ServerCubit>()
      .state
      .serverOn(ServerScope.readId(context))
      ?.user
      ?.id;

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
    // From initState it is already loading, and setState there would throw.
    if (!_isLoading || _loadFailed) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }
    final session = ServerScope.read(context);
    final members = MembersApi(session);
    final me = _me;
    final membership = await ChannelAccessApi(
      session,
    ).channelMembers(_channel.id);
    if (!mounted) return;

    // Resolved by id rather than picked out of a roster we no longer hold. A
    // member seated here may be anywhere in the alphabet, and the picker has
    // to draw them whether or not a search would have found them.
    final others = {...?membership?.memberIds}..remove(me);
    final rows = membership == null
        ? null
        : await members.membersByIdsOrNull(others.toList());
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (membership == null || rows == null) {
        _loadFailed = true;
        return;
      }
      _seated = membership.memberIds;
      _selection = MemberSelection.of(rows);
      // Only who is drawn. A seat whose name did not resolve is not in the
      // list, so it is never in a change either.
      _original = _selection.ids.toSet();
    });
  }

  /// People who could be seated here — never bots, never the caller.
  ///
  /// Bots are excluded by `change_channel_members` too; asking the database for
  /// people only is what stops the picker offering a row it would refuse.
  Future<List<ServerMember>> _search(String query) async {
    final me = _me;
    final results = await MembersApi(
      ServerScope.read(context),
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

    // Only what was ticked or unticked here. The caller is never in either:
    // removing yourself is leaving, and a private channel that loses its
    // last member is deleted.
    final selected = _selection.ids.toSet();
    final result = await ChannelAccessApi(ServerScope.read(context))
        .changeChannelMembers(
          channelId: _channel.id,
          isVoice: _channel.channelType == ChannelType.voice,
          add: selected.difference(_original),
          remove: _original.difference(selected),
          seated: {..._seated, ?_me},
        );
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (!result.success) _error = result.error;
    });
    if (result.success) {
      HelperMethods.showSuccess(message: 'Members saved');
      // Read again, so the list is who is in here now — somebody may have
      // left while the page was open.
      await _load();
    }
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
            onPressed: _changed && !_isSaving && !_loadFailed && !_isLoading
                ? _save
                : null,
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
          else if (_loadFailed) ...[
            const HintCard(
              icon: Icons.cloud_off_outlined,
              text: "Couldn't read who is in here.",
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Try again',
                variant: AppButtonVariant.secondary,
                onPressed: _load,
              ),
            ),
          ] else ...[
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
