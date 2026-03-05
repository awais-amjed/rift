import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/server.dart';
import '../../../../../logic/cubits/server/server_cubit.dart';
import '../../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../theme/custom_colors.dart';
import 'create_server_form.dart';
import 'join_server_form.dart';

enum _SelectorMode { list, pickMode, join, create }

/// Full-screen modal for selecting, adding, or managing servers.
class ServerSelectorDialog extends StatefulWidget {
  const ServerSelectorDialog({super.key});

  @override
  State<ServerSelectorDialog> createState() => _ServerSelectorDialogState();
}

class _ServerSelectorDialogState extends State<ServerSelectorDialog> {
  _SelectorMode _mode = _SelectorMode.list;

  String get _title {
    switch (_mode) {
      case _SelectorMode.list:
        return 'Select Server';
      case _SelectorMode.pickMode:
        return 'Add Server';
      case _SelectorMode.join:
        return 'Join Server';
      case _SelectorMode.create:
        return 'Create Server';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _SelectorMode.list:
        return 'Choose a server to view';
      case _SelectorMode.pickMode:
        return 'Join an existing server or create a new one';
      case _SelectorMode.join:
        return 'Enter your access token to join a server';
      case _SelectorMode.create:
        return 'Set up your own server with Supabase and LiveKit';
    }
  }

  void _handleSuccess() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Dialog(
          backgroundColor: themeState.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: themeState.borderPrimary),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448, maxHeight: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: themeState.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: themeState.textTertiary,
                              ),
                            ),
                          ],
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
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildContent(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    switch (_mode) {
      case _SelectorMode.list:
        return _ServerList(
          onAddServer: () => setState(() => _mode = _SelectorMode.pickMode),
          onClose: () => Navigator.of(context).pop(),
        );
      case _SelectorMode.pickMode:
        return _ModePicker(
          onJoin: () => setState(() => _mode = _SelectorMode.join),
          onCreate: () => setState(() => _mode = _SelectorMode.create),
          onBack: () => setState(() => _mode = _SelectorMode.list),
        );
      case _SelectorMode.join:
        return JoinServerForm(
          onSuccess: _handleSuccess,
          onCancel: () => setState(() => _mode = _SelectorMode.pickMode),
        );
      case _SelectorMode.create:
        return CreateServerForm(
          onSuccess: _handleSuccess,
          onCancel: () => setState(() => _mode = _SelectorMode.pickMode),
        );
    }
  }
}

class _ServerList extends StatelessWidget {
  final VoidCallback onAddServer;
  final VoidCallback onClose;

  const _ServerList({required this.onAddServer, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ServerCubit, ServerState>(
      builder: (context, state) {
        if (state.servers.isEmpty) {
          return _EmptyServerList(onAddServer: onAddServer);
        }

        return Column(
          children: [
            ...state.servers.map(
              (server) => _ServerListItem(
                server: server,
                isSelected: server.id == state.selectedServer?.id,
                canDelete: state.servers.length > 1,
                onTap: () {
                  context.read<ServerCubit>().setSelectedServer(server);
                  onClose();
                },
                onDelete: () {
                  context.read<ServerCubit>().removeServer(server.id);
                },
              ),
            ),
            const SizedBox(height: 12),
            _AddServerButton(onTap: onAddServer),
          ],
        );
      },
    );
  }
}

class _ServerListItem extends StatelessWidget {
  final Server server;
  final bool isSelected;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ServerListItem({
    required this.server,
    required this.isSelected,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: themeState.bgHover,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Avatar
                  _ServerAvatar(server: server),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeState.textPrimary,
                          ),
                        ),
                        Text(
                          server.supabaseUrl,
                          style: TextStyle(
                            fontSize: 11,
                            color: themeState.textTertiary,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Selected indicator
                  if (isSelected) ...[
                    Text(
                      'Active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: CustomColors.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: CustomColors.primary,
                    ),
                  ],
                  // Delete
                  if (canDelete)
                    IconButton(
                      onPressed: onDelete,
                      icon: Icon(
                        Icons.close,
                        size: 15,
                        color: themeState.textTertiary,
                      ),
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ServerAvatar extends StatelessWidget {
  final Server server;

  const _ServerAvatar({required this.server});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: CustomColors.primary,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        server.name.isNotEmpty ? server.name[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _AddServerButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddServerButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            hoverColor: themeState.bgHover,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: themeState.borderPrimary),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 18, color: CustomColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Add Server',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: CustomColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyServerList extends StatelessWidget {
  final VoidCallback onAddServer;

  const _EmptyServerList({required this.onAddServer});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Column(
          children: [
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: themeState.bgTertiary,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.dns_outlined,
                size: 32,
                color: themeState.textQuaternary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Servers Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: themeState.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Get started by adding your first server',
              style: TextStyle(fontSize: 13, color: themeState.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAddServer,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Your First Server'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CustomColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}

class _ModePicker extends StatelessWidget {
  final VoidCallback onJoin;
  final VoidCallback onCreate;
  final VoidCallback onBack;

  const _ModePicker({
    required this.onJoin,
    required this.onCreate,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ModeCard(
          icon: Icons.login,
          title: 'Join Server',
          subtitle: 'Connect to an existing server with an access token',
          onTap: onJoin,
        ),
        const SizedBox(height: 10),
        _ModeCard(
          icon: Icons.build_outlined,
          title: 'Create Server',
          subtitle: 'Set up your own server with Supabase and LiveKit',
          onTap: onCreate,
        ),
        const SizedBox(height: 16),
        TextButton(onPressed: onBack, child: const Text('Back to Servers')),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, themeState) {
        return Material(
          color: themeState.bgTertiary,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            hoverColor: themeState.bgHover,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeState.borderPrimary),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: themeState.bgSecondary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 22, color: CustomColors.primary),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: themeState.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: themeState.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: themeState.textTertiary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
