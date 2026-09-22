import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/services/member_selection.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/hint_card.dart';
import '../../../common/loading_dots.dart';
import '../../../common/message_banner.dart';
import '../../../theme/theme_context.dart';
import 'widgets/channel_member_picker.dart';

/// Who is in a private channel — and, for whoever runs it, who should be.
///
/// Open to every member of the room, not only its manager. Knowing who else can
/// read what you are about to say is the whole point of the room being private,
/// and it is not a thing you should have to hold a permission to find out.
class ChannelMembersDialog extends StatefulWidget {
  final Channel channel;

  const ChannelMembersDialog({super.key, required this.channel});

  @override
  State<ChannelMembersDialog> createState() => _ChannelMembersDialogState();
}

class _ChannelMembersDialogState extends State<ChannelMembersDialog> {
  MemberSelection _selection = MemberSelection.empty;

  /// Who was in the channel when the dialog opened, so Save can tell a real
  /// change from a tick-and-untick.
  Set<String> _original = {};

  bool _canManage = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  /// The one person who is always in it and is not in the list. Removing
  /// yourself is leaving, which is a different act with a different button.
  String? get _me => context.read<ServerCubit>().state.selectedServer?.user?.id;

  bool get _changed => _selection.differsFrom(_original);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    final me = _me;
    final membership = await cubit.channelMembers(widget.channel.id);
    if (!mounted) return;

    // Resolved by id rather than picked out of a roster we no longer hold. A
    // member seated here may be anywhere in the alphabet, and the picker has
    // to draw them whether or not a search would have found them.
    final seated = {...membership.memberIds}..remove(me);
    final rows = await cubit.membersByIds(seated.toList());
    if (!mounted) return;

    setState(() {
      _original = seated;
      _selection = MemberSelection.of(rows);
      _canManage = membership.canManage;
      _isLoading = false;
    });
  }

  /// People who could be seated here — never bots, never the caller.
  ///
  /// Bots are excluded by `set_channel_members` too; asking the database for
  /// people only is what stops the picker offering a row it would refuse.
  Future<List<ServerMember>> _search(String query) async {
    final me = _me;
    final results = await context.read<ServerCubit>().searchMembers(
      query: query,
      bots: false,
    );
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
      channelId: widget.channel.id,
      userIds: {?me, ..._selection.ids}.toList(),
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _isSaving = false;
        _error = result.error;
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AppModal(
      title: 'Who can see this',
      subtitle: '#${widget.channel.name}',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            MessageBanner(message: _error!, kind: MessageBannerKind.error),
            const SizedBox(height: 12),
          ],
          if (_isLoading)
            SizedBox(
              height: 200,
              child: Center(
                child: LoadingDots(
                  color: context.theme.accentBright,
                  dotSize: 6,
                ),
              ),
            )
          else ...[
            if (!_canManage) ...[
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
              enabled: _canManage && !_isSaving,
              onToggle: (member) =>
                  setState(() => _selection = _selection.toggled(member)),
            ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: _canManage ? 'Cancel' : 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        ),
        if (_canManage)
          AppButton(
            label: _isSaving ? 'Saving...' : 'Save',
            isLoading: _isSaving,
            onPressed: _changed && !_isSaving ? _save : null,
          ),
      ],
    );
  }
}
