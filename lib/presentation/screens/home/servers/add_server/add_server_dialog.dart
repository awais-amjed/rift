import 'package:flutter/material.dart';

import '../../../../../data/constants.dart';
import '../../../../common/app_modal.dart';
import 'create_server_modal.dart';
import 'join_server_modal.dart';
import 'widgets/server_mode_picker.dart';

enum _Step { pick, join, create }

/// Getting onto a server: pick join or create, then fill in the one you picked.
///
/// There used to be a server *list* in front of this, but switching servers
/// happens in the rail and the quick switcher — by the time this opens,
/// the only thing left to decide is join or create. On a first run the list was
/// empty anyway, so it asked the user to choose from nothing.
///
/// Each step is its own modal rather than a body swapped inside one shared
/// frame. A step's title, width and footer buttons all belong to the step —
/// holding them here meant three sets of each in a widget that only tracks
/// which one you're on.
class AddServerDialog extends StatefulWidget {
  const AddServerDialog({super.key});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  _Step _step = _Step.pick;

  void _handleSuccess() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      // The picker is two buttons that are their own commit, so this step has
      // no footer to put one in.
      _Step.pick => AppModal(
        title: 'Add Server',
        subtitle: 'Join an existing server or create a new one',
        maxWidth: K.dialogWidth,
        content: ServerModePicker(
          onJoin: () => setState(() => _step = _Step.join),
          onCreate: () => setState(() => _step = _Step.create),
        ),
      ),
      _Step.join => JoinServerModal(
        onSuccess: _handleSuccess,
        onCancel: () => setState(() => _step = _Step.pick),
      ),
      _Step.create => CreateServerModal(
        onSuccess: _handleSuccess,
        onCancel: () => setState(() => _step = _Step.pick),
      ),
    };
  }
}
