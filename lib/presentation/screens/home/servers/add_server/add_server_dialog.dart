import 'package:flutter/material.dart';

import '../../../../../data/classes/public_server.dart';
import '../../../../../data/constants.dart';
import '../../../../common/app_modal.dart';
import 'browse_servers_modal.dart';
import 'create_server_modal.dart';
import 'join_server_modal.dart';
import 'publish_new_server_modal.dart';
import 'widgets/server_mode_picker.dart';

enum _Step { pick, browse, join, create, publish }

/// Getting onto a server: pick how, then do it.
///
/// There used to be a server *list* in front of this, but switching servers
/// happens in the rail and the quick switcher — by the time this opens,
/// the only thing left to decide is how you are getting on.
///
/// Each step is its own modal rather than a body swapped inside one shared
/// frame. A step's title, width and footer buttons all belong to the step —
/// holding them here meant a set of each per step in a widget that only tracks
/// which one you're on.
class AddServerDialog extends StatefulWidget {
  /// An invite that came from outside the app, if that is why this opened.
  ///
  /// Skips straight to the join step with the link already in hand: someone
  /// who tapped an invite has said which server they mean, and asking them to
  /// pick "join" from a menu first is asking a question they just answered.
  final String? inviteLink;

  const AddServerDialog({super.key, this.inviteLink});

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  late _Step _step = widget.inviteLink == null ? _Step.pick : _Step.join;

  /// The listing picked in the browser, carried into the join step so it can
  /// skip the invite field. Null when the link was typed.
  PublicServer? _picked;

  void _handleSuccess() => Navigator.of(context).pop();

  /// Where a finished join goes next.
  ///
  /// An ordinary joiner is done — whether the server is findable is not their
  /// call. An admin is not: joining is how somebody arrives at a server the
  /// self-hosted console made for them, and that route skipped every question
  /// the create flow asks. So they get the same last step, from the same
  /// place, rather than having to find it later under a context menu.
  void _handleJoined({required bool joinedAsAdmin}) =>
      joinedAsAdmin ? _go(_Step.publish) : _handleSuccess();

  void _go(_Step step, {PublicServer? listing}) => setState(() {
    _step = step;
    _picked = listing;
  });

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      // The picker is cards that are their own commit, so this step has no
      // footer to put one in.
      _Step.pick => AppModal(
        title: 'Add server',
        subtitle:
            'Find a server, join one you were invited to, or make your own',
        maxWidth: K.dialogWidth,
        content: ServerModePicker(
          onBrowse: () => _go(_Step.browse),
          onJoin: () => _go(_Step.join),
          onCreate: () => _go(_Step.create),
        ),
      ),
      _Step.browse => BrowseServersModal(
        onJoin: (listing) => _go(_Step.join, listing: listing),
        onCancel: () => _go(_Step.pick),
      ),
      _Step.join => JoinServerModal(
        listing: _picked,
        inviteLink: widget.inviteLink,
        onSuccess: _handleJoined,
        // Back where you came from: the browser if you picked a server there,
        // the picker if you typed a link.
        onCancel: () =>
            _go(_picked == null ? _Step.pick : _Step.browse, listing: _picked),
      ),
      // Creating one asks whether it should be findable, and so does joining
      // one *as its admin* — see [_handleJoined]. An ordinary joiner is not
      // asked, because it is not their call to make.
      _Step.create => CreateServerModal(
        onSuccess: () => _go(_Step.publish),
        onCancel: () => _go(_Step.pick),
      ),
      _Step.publish => PublishNewServerModal(onDone: _handleSuccess),
    };
  }
}
