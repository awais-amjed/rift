import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/resolved_invite.dart';
import '../../../../../data/constants.dart';
import '../../../../../logic/cubits/public_servers/public_servers_cubit.dart';
import '../../../../../logic/cubits/supabase_backup/supabase_backup_cubit.dart';
import '../../../../common/app_modal.dart';
import 'browse_servers_modal.dart';
import 'create_server_modal.dart';
import 'invite_link_modal.dart';
import 'join_server_modal.dart';
import 'publish_new_server_modal.dart';
import 'widgets/server_mode_picker.dart';

enum _Step { pick, browse, link, join, create, publish }

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
  late _Step _step = widget.inviteLink == null ? _Step.pick : _Step.link;

  /// The invite the join step is for, once the link step — or the browser —
  /// has produced one.
  ResolvedInvite? _invite;

  /// Whether [_invite] came from the browser, which is where Back goes then.
  bool _fromBrowser = false;

  void _handleSuccess() => Navigator.of(context).pop();

  /// Where a finished join goes next.
  ///
  /// An ordinary joiner is done — whether the server is findable is not their
  /// call. An admin is not: joining is how somebody arrives at a server the
  /// self-hosted console made for them, and that route skipped every question
  /// the create flow asks. So they get the same last step, from the same
  /// place, rather than having to find it later under a context menu.
  ///
  /// Unless the question has been answered. A server picked out of the
  /// browser is listed by definition, and one somebody else already listed
  /// has nothing left to ask — a second "list publicly" would only be
  /// refused as a duplicate.
  Future<void> _handleJoined({required bool joinedAsAdmin}) async {
    if (!joinedAsAdmin || _fromBrowser) return _handleSuccess();
    final invite = _invite;
    if (invite != null &&
        context.read<SupabaseBackupCubit>().state.isSignedIn) {
      final listed = await context.read<PublicServersCubit>().isListed(
        supabaseUrl: invite.serverUrl,
        serverId: invite.serverId,
      );
      if (!mounted) return;
      if (listed) return _handleSuccess();
    }
    setState(() => _joined = true);
    _go(_Step.publish);
  }

  void _go(_Step step) => setState(() => _step = step);

  /// Whether the publish step follows a join rather than a create, which is
  /// all that changes what it is headed.
  bool _joined = false;

  void _join(ResolvedInvite invite, {required bool fromBrowser}) =>
      setState(() {
        _invite = invite;
        _fromBrowser = fromBrowser;
        _step = _Step.join;
      });

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      // The picker is cards that are their own commit, so this step has no
      // footer to put one in.
      _Step.pick => AppModal(
        pageOnPhone: true,
        title: 'Add server',
        subtitle:
            'Find a server, join one you were invited to, or make your own',
        maxWidth: K.dialogWidth,
        content: ServerModePicker(
          onBrowse: () => _go(_Step.browse),
          onJoin: () => _go(_Step.link),
          onCreate: () => _go(_Step.create),
        ),
      ),
      _Step.browse => BrowseServersModal(
        // A listing already names its server and carries a working invite,
        // so it skips the link step entirely.
        onJoin: (listing) =>
            _join(ResolvedInvite.fromListing(listing), fromBrowser: true),
        onCancel: () => _go(_Step.pick),
      ),
      // The link on its own first, so a bad one is refused before anybody has
      // typed a name for it. A tapped invite arrives here already filled in.
      _Step.link => InviteLinkModal(
        initialLink: widget.inviteLink,
        onResolved: (invite) => _join(invite, fromBrowser: false),
        onCancel: () => _go(_Step.pick),
      ),
      _Step.join => JoinServerModal(
        invite: _invite!,
        onSuccess: _handleJoined,
        // Back where you came from: the browser if you picked a server there,
        // the link if you typed one.
        onCancel: () => _go(_fromBrowser ? _Step.browse : _Step.link),
      ),
      // Creating one asks whether it should be findable, and so does joining
      // one *as its admin* — see [_handleJoined]. An ordinary joiner is not
      // asked, because it is not their call to make.
      _Step.create => CreateServerModal(
        onSuccess: () => _go(_Step.publish),
        onCancel: () => _go(_Step.pick),
      ),
      _Step.publish => PublishNewServerModal(
        onDone: _handleSuccess,
        joined: _joined,
      ),
    };
  }
}
