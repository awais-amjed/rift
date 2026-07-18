import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/theme/theme_cubit.dart';
import '../create_server_form.dart';
import '../join_server_form.dart';
import 'widgets/server_list_view.dart';
import 'widgets/server_mode_picker.dart';

enum _SelectorMode { list, pickMode, join, create }

/// Full-screen modal for selecting, adding, or managing servers.
///
/// Switching between joined servers now happens in the anchored
/// [ServerSwitcherPopover]; this dialog is opened for the add / join / create
/// flows (via [startAtAddFlow]) and remains the fallback list view.
class ServerSelectorDialog extends StatefulWidget {
  /// Open directly on the "Add Server" step instead of the server list.
  final bool startAtAddFlow;

  const ServerSelectorDialog({super.key, this.startAtAddFlow = false});

  @override
  State<ServerSelectorDialog> createState() => _ServerSelectorDialogState();
}

class _ServerSelectorDialogState extends State<ServerSelectorDialog> {
  late _SelectorMode _mode =
      widget.startAtAddFlow ? _SelectorMode.pickMode : _SelectorMode.list;

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
        return 'Join a server with an invite link';
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
        return ServerListView(
          onAddServer: () => setState(() => _mode = _SelectorMode.pickMode),
          onClose: () => Navigator.of(context).pop(),
        );
      case _SelectorMode.pickMode:
        return ServerModePicker(
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
