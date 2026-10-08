import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/apis/members_api.dart';
import '../../../../data/classes/server_member.dart';
import '../../../../data/classes/user_permissions.dart';
import '../../../../data/enums/channel_type.dart';
import '../../../../data/enums/server_permission.dart';
import '../../../../data/repositories/session_repository.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../../logic/services/member_selection.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import '../../settings/widgets/setting_toggle_row.dart';
import 'widgets/channel_member_picker.dart';
import 'widgets/channel_type_toggle.dart';

/// Dialog to create a new channel (text or voice) in the current server.
class CreateChannelDialog extends StatefulWidget {
  /// Which kind the dialog opens on — the section whose "+" was pressed. The
  /// toggle still offers the other one; this only decides where it starts.
  final ChannelType initialType;

  const CreateChannelDialog({super.key, this.initialType = ChannelType.text});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final _nameCtrl = TextEditingController();

  late ChannelType _type = widget.initialType;
  bool _isPrivate = false;

  /// Somebody who may only make private channels gets one, with the switch
  /// held down rather than hidden — a control that is missing reads as a bug,
  /// and one that is fixed with a reason reads as a rule.
  late final bool _mayMakePublic =
      _permissions?.can(ServerPermission.manageChannels) ?? false;
  bool _isLoading = false;
  String? _error;

  /// Everyone but this device's own member row and the bots — see
  /// [ChannelMemberPicker] for why neither belongs in the list.
  MemberSelection _selection = MemberSelection.empty;

  UserPermissions? get _permissions =>
      context.read<ServerCubit>().state.myPermissions;

  bool get _canSubmit => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isPrivate = !_mayMakePublic;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// People who could be seated in this channel — never bots, never the
  /// creator, who is always in it and so is never drawn as a checkbox.
  ///
  /// Asked of the database on every keystroke rather than filtered out of a
  /// roster held in memory. The roster arrives a page at a time now, and a
  /// local filter over one page is a filter that answers "No matches" about
  /// somebody who is really there.
  Future<List<ServerMember>> _searchMembers(String query) async {
    final me = context.read<ServerCubit>().state.selectedServer?.user?.id;
    final results = await MembersApi(
      session: context.read<SessionRepository>(),
    ).searchMembers(query: query, bots: false);
    return [
      for (final member in results)
        if (member.id != me) member,
    ];
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await context.read<ServerCubit>().createChannel(
      name: _nameCtrl.text.trim(),
      channelType: _type.name,
      isPrivate: _isPrivate,
      memberIds: _isPrivate ? _selection.ids.toList() : const [],
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    HelperMethods.showSuccess(message: 'Channel created');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    final serverName = context.read<ServerCubit>().state.selectedServer?.name;
    return AppModal(
      title: 'Create channel',
      // Which server it lands in, as the other dialogs that act on one say.
      subtitle: serverName == null ? null : 'In $serverName',
      error: _error,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: 'Channel name',
            hint: 'general',
            enabled: !_isLoading,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 16),
          Text(
            'CHANNEL TYPE',
            style: AppText.sectionLabel.copyWith(
              color: themeState.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          ChannelTypeToggle(
            value: _type,
            onChanged: _isLoading ? null : (t) => setState(() => _type = t),
          ),
          const SizedBox(height: 16),
          // The description says what actually differs, and says the part
          // people get wrong: an admin is outside this too, because an
          // admin holds no key to it either (ARCHITECTURE.md §4).
          SettingToggleRow(
            title: 'Private channel',
            description: _mayMakePublic
                ? 'Only the people you pick can see it — server admins '
                      'included. You can add or remove people later.'
                : 'Only the people you pick can see it. Making a channel '
                      'the whole server can see needs the manage-channels '
                      'permission.',
            value: _isPrivate,
            onChanged: _isLoading || !_mayMakePublic
                ? null
                : (v) => setState(() => _isPrivate = v),
          ),
          if (_isPrivate) ...[
            const SizedBox(height: 16),
            ChannelMemberPicker(
              selection: _selection,
              onSearch: _searchMembers,
              enabled: !_isLoading,
              onToggle: (member) =>
                  setState(() => _selection = _selection.toggled(member)),
            ),
          ],
        ],
      ),
      actions: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.secondary,
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        AppButton(
          label: _isLoading ? 'Creating...' : 'Create channel',
          isLoading: _isLoading,
          onPressed: _canSubmit && !_isLoading ? _submit : null,
        ),
      ],
    );
  }
}
