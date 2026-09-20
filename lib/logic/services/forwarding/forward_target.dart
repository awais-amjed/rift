import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';

/// Somewhere a message can be forwarded to.
///
/// Three kinds because there are three places a message can live, each with
/// its own key problem: a channel has a wrapped symmetric key, a server DM
/// derives one from the two chat identities on that host, and a central DM
/// does the same on central. A destination that named only an id would leave
/// the sender guessing which.
sealed class ForwardTarget {
  const ForwardTarget();

  /// Stable across a rebuild of the list — what a selection is remembered by.
  String get id;

  /// What the row says, and what the forwarded message is filed under.
  String get label;

  /// The line under it: which server, or which tier a DM is on.
  String get context;
}

class ChannelTarget extends ForwardTarget {
  final Server server;
  final Channel channel;

  const ChannelTarget({required this.server, required this.channel});

  @override
  String get id => 'channel:${server.id}:${channel.id}';

  @override
  String get label => '#${channel.name}';

  @override
  String get context => server.name;
}

class ServerDmTarget extends ForwardTarget {
  final Server server;
  final String peerId;
  final String peerName;

  /// The peer's X25519 key, carried on the target rather than looked up at
  /// send time: the conversation list already answered for it, and a DM
  /// whose key cannot be derived is one this list should not have offered.
  final String? peerChatPublicKey;

  const ServerDmTarget({
    required this.server,
    required this.peerId,
    required this.peerName,
    this.peerChatPublicKey,
  });

  @override
  String get id => 'dm:${server.id}:$peerId';

  @override
  String get label => peerName;

  @override
  String get context => '${server.name} · direct message';
}

class CentralDmTarget extends ForwardTarget {
  final String peerId;
  final String peerHandle;
  final String? peerChatPublicKey;

  const CentralDmTarget({
    required this.peerId,
    required this.peerHandle,
    this.peerChatPublicKey,
  });

  @override
  String get id => 'central:$peerId';

  @override
  String get label => '@$peerHandle';

  @override
  String get context => 'Rift · direct message';
}

/// Filtering the destination list as somebody types.
///
/// Matches the label and the context both, so "proxy" finds every channel on
/// a server called Proxy Test and a person's name finds them wherever they
/// are. Pure, so the ranking is the same on every platform and testable
/// without a widget.
abstract final class ForwardTargetSearch {
  static List<ForwardTarget> filter(List<ForwardTarget> targets, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return targets;
    final starts = <ForwardTarget>[];
    final contains = <ForwardTarget>[];
    for (final target in targets) {
      final label = target.label.toLowerCase();
      // The sigil is chrome, not part of the name: typing "gen" should find
      // #general, and nobody types the hash.
      final bare = label.replaceFirst(RegExp(r'^[#@]'), '');
      if (bare.startsWith(needle) || label.startsWith(needle)) {
        starts.add(target);
      } else if (bare.contains(needle) ||
          target.context.toLowerCase().contains(needle)) {
        contains.add(target);
      }
    }
    return [...starts, ...contains];
  }
}
