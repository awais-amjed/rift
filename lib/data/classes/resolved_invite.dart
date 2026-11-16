import 'package:equatable/equatable.dart';

import 'public_server.dart';

/// An invite the server has vouched for: its address and code, and the name
/// of the server they open.
///
/// Joining is two steps now — the link first, then how you will appear — and
/// this is what the first hands to the second. It exists so the second step
/// never sees a raw link: by the time somebody is asked for a username, the
/// invite has been read and the server has answered to it.
class ResolvedInvite extends Equatable {
  final String serverUrl;
  final String inviteCode;
  final String serverId;
  final String serverName;

  /// The server's icon in its public `servers` bucket, for the join screen.
  /// Null from a listing, whose picture is central's copy, not the server's.
  final String? iconPath;

  /// Joining needs a Rift account: an admin marked this link, and the server
  /// wants central to vouch for whoever comes through it. Unknown (false)
  /// from a listing until its invite has been read.
  final bool needsAccount;

  const ResolvedInvite({
    required this.serverUrl,
    required this.inviteCode,
    required this.serverId,
    required this.serverName,
    this.iconPath,
    this.needsAccount = false,
  });

  /// A listing already names its server and carries a working invite, so
  /// arriving from the browser needs no round trip to get here.
  factory ResolvedInvite.fromListing(PublicServer listing) => ResolvedInvite(
    serverUrl: listing.supabaseUrl,
    inviteCode: listing.inviteCode,
    serverId: listing.serverId,
    serverName: listing.name,
  );

  /// The one line of provenance to show before asking for a username.
  String get host => Uri.tryParse(serverUrl)?.host ?? serverUrl;

  @override
  List<Object?> get props => [
    serverUrl,
    inviteCode,
    serverId,
    serverName,
    iconPath,
    needsAccount,
  ];
}

/// Whether a server's `resolve_invite` answer says the link needs a Rift
/// account. A server from before the switch does not say, which is no.
bool needsAccountIn(Map<dynamic, dynamic> data) => data['needs_account'] == true;
