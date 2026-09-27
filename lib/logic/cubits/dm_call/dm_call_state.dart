part of 'dm_call_cubit.dart';

/// A call ringing this device, and where.
class IncomingDmCall {
  final String serverId;
  final String serverName;
  final DmCall call;

  const IncomingDmCall({
    required this.serverId,
    required this.serverName,
    required this.call,
  });
}

/// The call this device is on — placed here, or answered here.
class ActiveDmCall {
  final String serverId;

  /// The row as last read. Ringing until the other end answers.
  final DmCall call;

  const ActiveDmCall({required this.serverId, required this.call});

  ActiveDmCall withCall(DmCall next) =>
      ActiveDmCall(serverId: serverId, call: next);
}

/// Calls between two members, on every server this device is on: the ones
/// ringing it, and the one it is in.
class DmCallState {
  /// Newest first. Several at once is rare but real — two people calling in
  /// the same minute, on one server or two.
  final List<IncomingDmCall> incoming;

  final ActiveDmCall? active;

  /// A ring or an answer is on its way to the server, so the buttons that
  /// would send a second one are held.
  final bool busy;

  const DmCallState({
    this.incoming = const [],
    this.active,
    this.busy = false,
  });

  /// Our own call, still waiting for the other end to pick up.
  bool get isRingingOut => active?.call.isRinging ?? false;

  /// Whether [peerId] on [serverId] is who we are in a call with, or ringing.
  bool isWith(String serverId, String peerId) =>
      active?.serverId == serverId && active?.call.peerId == peerId;

  DmCallState copyWith({
    List<IncomingDmCall>? incoming,
    ActiveDmCall? active,
    bool clearActive = false,
    bool? busy,
  }) => DmCallState(
    incoming: incoming ?? this.incoming,
    active: clearActive ? null : (active ?? this.active),
    busy: busy ?? this.busy,
  );
}
