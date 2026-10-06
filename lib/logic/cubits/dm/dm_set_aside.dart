part of 'dm_cubit.dart';

/// A server DM closed only because a central one opened, kept so it opens
/// again when the person comes back to the server's DMs.
///
/// Only one DM surface is open at a time, so opening a central conversation
/// closes the server one. That close was a side effect, not a choice: the
/// person went Home for a moment, and coming back found the DM list with
/// nothing open. A close they *did* choose — the conversation's X, declining
/// a request — forgets it, and so does opening anybody else or switching
/// server, where the DM key it would need is gone.
mixin _DmSetAsideMixin on Cubit<DmState> {
  /// Implemented by the history mixin.
  Future<void> openConversation({
    required String peerId,
    required String peerName,
    required String? peerChatKey,
    bool again,
  });
  void closeConversation();

  ({String peerId, String peerName})? _setAside;

  /// Closes the open conversation for a central one, remembering it.
  void setAsideConversation() {
    final peerId = state.openPeerId;
    if (peerId == null) return;
    final peerName = state.openPeerName ?? '';
    closeConversation();
    _setAside = (peerId: peerId, peerName: peerName);
  }

  /// Opens the conversation set aside, if one is waiting and nothing else
  /// has been opened since.
  Future<void> resumeSetAside() async {
    final aside = _setAside;
    _setAside = null;
    if (aside == null || state.openPeerId != null) return;
    final listed = state.conversations
        .where((c) => c.peerId == aside.peerId)
        .firstOrNull;
    await openConversation(
      peerId: aside.peerId,
      peerName: listed?.peerName ?? aside.peerName,
      // Already worked out when it was first opened; the listed key is the
      // one to check it against if the peer has published a new one since.
      peerChatKey: listed?.peerChatPublicKey,
    );
  }

  void _forgetSetAside() => _setAside = null;
}
