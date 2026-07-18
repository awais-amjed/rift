import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server_member.dart';
import '../../../../../logic/cubits/central_dm/central_dm_cubit.dart' as central;
import '../../../../../logic/cubits/dm/dm_cubit.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../common/app_modal.dart';

/// Member picker for starting a DM on the selected server. Members without a
/// published chat key are listed but disabled (they must open the app once).
class NewServerDmDialog extends StatefulWidget {
  const NewServerDmDialog({super.key});

  static void show(BuildContext context) {
    showCustomDialog(
      context: context,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: context.read<ServerCubit>()),
          BlocProvider.value(value: context.read<DmCubit>()),
          BlocProvider.value(value: context.read<central.CentralDmCubit>()),
        ],
        child: const NewServerDmDialog(),
      ),
    );
  }

  @override
  State<NewServerDmDialog> createState() => _NewServerDmDialogState();
}

class _NewServerDmDialogState extends State<NewServerDmDialog> {
  List<ServerMember>? _members;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await context.read<ServerCubit>().listMembers();
    if (!mounted) return;
    setState(() {
      _members = result.members;
      _error = result.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeState = context.watch<ThemeCubit>().state;
    final localUserId =
        context.read<ServerCubit>().state.selectedServer?.user?.id;

    return AppModal(
      title: 'New Direct Message',
      content: SizedBox(
        width: 380,
        height: 320,
        child: _error != null
            ? Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: themeState.textTertiary),
                ),
              )
            : _members == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      for (final member in _members!)
                        if (member.id != localUserId && !member.isBanned)
                          _MemberRow(
                            member: member,
                            themeState: themeState,
                            onTap: member.chatPublicKey == null
                                ? null
                                : () {
                                    context
                                        .read<central.CentralDmCubit>()
                                        .closeConversation();
                                    context.read<DmCubit>().openConversation(
                                          peerId: member.id,
                                          peerName: member.displayName,
                                          peerChatKey: member.chatPublicKey,
                                        );
                                    Navigator.of(context).pop();
                                  },
                          ),
                    ],
                  ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final ServerMember member;
  final ThemeState themeState;
  final VoidCallback? onTap;

  const _MemberRow({
    required this.member,
    required this.themeState,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        hoverColor: themeState.bgHover,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 18,
                color: enabled
                    ? themeState.textTertiary
                    : themeState.textQuaternary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  member.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    color: enabled
                        ? themeState.textPrimary
                        : themeState.textQuaternary,
                  ),
                ),
              ),
              if (!enabled)
                Text(
                  'no chat keys yet',
                  style: TextStyle(
                    fontSize: 11,
                    color: themeState.textQuaternary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
