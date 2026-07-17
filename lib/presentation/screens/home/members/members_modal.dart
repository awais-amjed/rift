import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/classes/server_member.dart';
import '../../../../logic/cubits/server/server_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/custom_colors.dart';
import 'widgets/member_row.dart';

/// Members dialog — lists everyone on the server with their permissions and
/// moderation state. Server admins manage permissions here (Discord-style:
/// invites grant nothing, promotion happens after joining); admins and
/// channel managers get mute/deafen controls.
class MembersModal extends StatefulWidget {
  const MembersModal({super.key});

  @override
  State<MembersModal> createState() => _MembersModalState();
}

class _MembersModalState extends State<MembersModal> {
  List<ServerMember>? _members;
  String? _error;
  String? _expandedId;

  /// Member id with an in-flight permission/moderation call.
  String? _busyId;

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

  Future<void> _setPermission(
    ServerMember member, {
    bool? isServerAdmin,
    bool? isChannelManager,
    bool? canCreateTokens,
  }) async {
    setState(() => _busyId = member.id);
    final response = await context.read<ServerCubit>().setUserPermissions(
          userId: member.id,
          isServerAdmin: isServerAdmin,
          isChannelManager: isChannelManager,
          canCreateTokens: canCreateTokens,
        );
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (response.success) {
        final updated = member.copyWith(
          permissions: member.permissions.copyWith(
            isServerAdmin: isServerAdmin,
            isChannelManager: isChannelManager,
            canCreateTokens: canCreateTokens,
          ),
        );
        _members = _members!
            .map((m) => m.id == member.id ? updated : m)
            .toList();
      } else {
        _error = response.error;
      }
    });
  }

  Future<void> _moderate(
    ServerMember member, {
    bool? muted,
    bool? deafened,
  }) async {
    setState(() => _busyId = member.id);
    final response = await context.read<ServerCubit>().moderateUser(
          userId: member.id,
          isMuted: muted,
          isDeafened: deafened,
        );
    if (!mounted) return;
    setState(() {
      _busyId = null;
      if (response.success) {
        _members = _members!
            .map((m) => m.id == member.id
                ? m.copyWith(isMuted: muted, isDeafened: deafened)
                : m)
            .toList();
      } else {
        _error = response.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        final viewer =
            context.watch<ServerCubit>().state.selectedServer?.user;
        final viewerPerms = viewer?.permissions;
        final viewerIsAdmin = viewerPerms?.isServerAdmin ?? false;
        final viewerIsModerator =
            viewerIsAdmin || (viewerPerms?.isChannelManager ?? false);

        return Dialog(
          backgroundColor: themeState.bgPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448, maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 14, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: themeState.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.group_outlined,
                          size: 18,
                          color: themeState.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _members == null
                              ? 'Members'
                              : 'Members — ${_members!.length}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: themeState.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(
                          Icons.close,
                          size: 18,
                          color: themeState.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: themeState.borderPrimary),

                // ── Body ────────────────────────────────────────────
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CustomColors.error,
                      ),
                    ),
                  ),
                if (_members == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )
                else if (_members != null)
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: _members!.length,
                      itemBuilder: (context, index) {
                        final member = _members![index];
                        final isSelf = member.id == viewer?.id;
                        return MemberRow(
                          member: member,
                          isSelf: isSelf,
                          isExpanded: _expandedId == member.id,
                          isBusy: _busyId == member.id,
                          // Admins manage permissions for everyone but
                          // themselves (the server rejects self-edits).
                          canManagePermissions: viewerIsAdmin && !isSelf,
                          // Moderators mute/deafen non-admins.
                          canModerate: viewerIsModerator &&
                              !isSelf &&
                              !member.permissions.isServerAdmin,
                          onTap: () => setState(() {
                            _expandedId =
                                _expandedId == member.id ? null : member.id;
                          }),
                          onPermissionChanged: (
                                  {isServerAdmin,
                                  isChannelManager,
                                  canCreateTokens}) =>
                              _setPermission(
                            member,
                            isServerAdmin: isServerAdmin,
                            isChannelManager: isChannelManager,
                            canCreateTokens: canCreateTokens,
                          ),
                          onModerate: ({muted, deafened}) =>
                              _moderate(member, muted: muted, deafened: deafened),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
