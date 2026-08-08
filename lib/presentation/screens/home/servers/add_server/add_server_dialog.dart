import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_modal.dart';
import '../create_server_form.dart';
import '../join_server_form.dart';
import 'widgets/server_mode_picker.dart';

enum _Step { pick, join, create }

/// The choice step is two cards side by side, so it wants more room than a
/// column of fields does.
const _pickWidth = 660.0;

/// Getting onto a server: pick join or create, then fill in the one you picked.
///
/// There used to be a server *list* in front of this, but switching servers
/// happens in the rail and the quick switcher — by the time this opens,
/// the only thing left to decide is join or create. On a first run the list was
/// empty anyway, so it asked the user to choose from nothing.
class AddServerDialog extends StatefulWidget {
  const AddServerDialog({super.key});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  _Step _step = _Step.pick;

  String get _title => switch (_step) {
    _Step.pick => 'Add Server',
    _Step.join => 'Join Server',
    _Step.create => 'Create Server',
  };

  String get _subtitle => switch (_step) {
    _Step.pick => 'Join an existing server or create a new one',
    _Step.join => 'Join a server with an invite link',
    _Step.create => 'Set up your own server with Supabase and LiveKit',
  };

  void _handleSuccess() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    // Full-page: the create form alone is six fields and two section headers,
    // and the join flow follows it with more. A box sized to its content spent
    // the whole flow scrolling inside a window with room to spare.
    return AppModal(
      title: _title,
      subtitle: _subtitle,
      fullPage: true,
      maxWidth: _step == _Step.pick ? _pickWidth : K.dialogContentWidth,
      content: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (_step) {
      case _Step.pick:
        return ServerModePicker(
          onJoin: () => setState(() => _step = _Step.join),
          onCreate: () => setState(() => _step = _Step.create),
        );
      case _Step.join:
        return JoinServerForm(
          onSuccess: _handleSuccess,
          onCancel: () => setState(() => _step = _Step.pick),
        );
      case _Step.create:
        return CreateServerForm(
          onSuccess: _handleSuccess,
          onCancel: () => setState(() => _step = _Step.pick),
        );
    }
  }
}
