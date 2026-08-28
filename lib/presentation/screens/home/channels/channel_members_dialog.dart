import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/channel.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/hint_card.dart';
import '../../../common/message_banner.dart';
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
  final _searchCtrl = TextEditingController();

  List<ServerMember> _members = const [];
  Set<String> _selected = {};
  Set<String> _original = {};
  String _query = '';

  bool _canManage = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  /// The one person who is always in it and is not in the list. Removing
  /// yourself is leaving, which is a different act with a different button.
  String? get _me => context.read<ServerCubit>().state.selectedServer?.user?.id;

  bool get _changed =>
      _selected.length != _original.length || !_selected.containsAll(_original);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cubit = context.read<ServerCubit>();
    final me = _me;
    final membership = await cubit.channelMembers(widget.channel.id);
    final roster = await cubit.listMembers();
    if (!mounted) return;

    setState(() {
      _members = (roster.members ?? const [])
          .where((m) => !m.isBot && !m.isBanned && m.id != me)
          .toList();
      _original = {...membership.memberIds}..remove(me);
      _selected = {..._original};
      _canManage = membership.canManage;
      _isLoading = false;
    });
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
      userIds: {?me, ..._selected}.toList(),
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
    final themeState = context.watch<ThemeCubit>().state;

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
            const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
              themeState: themeState,
              members: _members,
              selected: _selected,
              query: _query,
              queryController: _searchCtrl,
              enabled: _canManage && !_isSaving,
              onQueryChanged: (q) => setState(() => _query = q),
              onToggle: (id) => setState(() {
                _selected.contains(id)
                    ? _selected.remove(id)
                    : _selected.add(id);
              }),
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
