import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../data/enums/channel_type.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/helper_methods.dart';
import '../../../common/app_button.dart';
import '../../../common/app_modal.dart';
import '../../../common/app_text_field.dart';
import '../../../common/message_banner.dart';
import '../../../theme/app_text.dart';
import '../../settings/widgets/setting_toggle_row.dart';
import 'widgets/channel_member_picker.dart';
import 'widgets/channel_type_toggle.dart';

/// Dialog to create a new channel (text or voice) in the current server.
class CreateChannelDialog extends StatefulWidget {
  const CreateChannelDialog({super.key});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  ChannelType _type = ChannelType.text;
  bool _isPrivate = false;
  bool _isLoading = false;
  String? _error;

  /// Everyone but this device's own member row and the bots — see
  /// [ChannelMemberPicker] for why neither belongs in the list.
  List<ServerMember> _members = const [];
  final Set<String> _selected = {};
  String _query = '';

  bool get _canSubmit => _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Loaded on open rather than when the toggle is flipped: the list is the
  /// slowest thing in this dialog, and somebody who ticks "private" has already
  /// decided — making them wait at that point would be the one moment it shows.
  Future<void> _loadMembers() async {
    final cubit = context.read<ServerCubit>();
    final me = cubit.state.selectedServer?.user?.id;
    final result = await cubit.listMembers();
    if (!mounted || result.members == null) return;
    setState(() {
      _members = result.members!
          .where((m) => !m.isBot && !m.isBanned && m.id != me)
          .toList();
    });
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
      memberIds: _isPrivate ? _selected.toList() : const [],
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _error = result.error;
        _isLoading = false;
      });
      return;
    }

    HelperMethods.showSuccess(message: 'Channel created!');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return AppModal(
          title: 'Create Channel',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null) ...[
                MessageBanner(message: _error!, kind: MessageBannerKind.error),
                const SizedBox(height: 12),
              ],
              AppTextField(
                controller: _nameCtrl,
                label: 'Channel Name',
                hint: 'general',
                enabled: !_isLoading,
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text(
                'CHANNEL TYPE',
                style: AppText.sectionLabel.copyWith(
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                  color: themeState.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              ChannelTypeToggle(
                value: _type,
                onChanged: _isLoading
                    ? null
                    : (t) => setState(() => _type = t),
              ),
              const SizedBox(height: 16),
              // The description says what actually differs, and says the part
              // people get wrong: an admin is outside this too, because an
              // admin holds no key to it either (ARCHITECTURE.md §4).
              SettingToggleRow(
                themeState: themeState,
                title: 'Private channel',
                description:
                    'Only the people you pick can see it — server admins '
                    'included. You can add or remove people later.',
                value: _isPrivate,
                onChanged: _isLoading
                    ? null
                    : (v) => setState(() => _isPrivate = v),
              ),
              if (_isPrivate) ...[
                const SizedBox(height: 16),
                ChannelMemberPicker(
                  themeState: themeState,
                  members: _members,
                  selected: _selected,
                  query: _query,
                  queryController: _searchCtrl,
                  enabled: !_isLoading,
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
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
            AppButton(
              label: _isLoading ? 'Creating...' : 'Create Channel',
              isLoading: _isLoading,
              onPressed: _canSubmit && !_isLoading ? _submit : null,
            ),
          ],
        );
      },
    );
  }
}
