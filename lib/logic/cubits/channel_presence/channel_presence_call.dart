part of 'channel_presence_cubit.dart';

/// Keeping our place on the call's server while another server is selected.
///
/// Everything else in this cubit is about the selected server, and opening
/// another one used to take all of it down — the call's server included. The
/// presence join went, so for everybody there we went offline, and with it
/// the location presence vouches for: they saw us leave a call we were still
/// talking in. The new server, meanwhile, was told we were in a channel it
/// does not have.
///
/// So while the call is on a server that is not the selected one, this holds
/// that server's two topics on its own: our presence entry, and the voice
/// topic our location and screen are announced on. Both are shared joins
/// ([ServerRealtime]): it takes them before the selected side lets go, and
/// lets go only after the selected side has them again, so a switch either
/// way leaves nothing and nobody there sees us blink.
mixin _CallSideMixin on Cubit<ChannelPresenceState> {
  SessionRepository get _session;
  LiveKitCubit get _livekitCubit;
  String? get _currentServerId;
  bool get _tracked;

  _CallSide? _callSide;

  /// Bring the call's side in line with the call and the selection.
  ///
  /// With [mayRelease] false it only ever takes the call's server on: what a
  /// switch calls before the selected side drops its joins, when letting go
  /// here would leave a gap.
  void _syncCallSide({bool mayRelease = true}) {
    if (isClosed) return;
    final lk = _livekitCubit.state;
    final callServerId = lk.currentChannelId == null
        ? null
        : lk.currentServerId;
    final wanted =
        callServerId == null || callServerId == _session.selectedServerId
        ? null
        : _session.serverById(callServerId);

    final side = _callSide;
    if (side != null && side.serverId != wanted?.id) {
      if (!mayRelease && wanted == null) return;
      _callSide = null;
      // Handed back to the selected side, which says where we are itself.
      // Otherwise the call has left that server, and everybody there should
      // hear so now rather than when presence gives up on us.
      final stillThere =
          lk.currentChannelId != null && lk.currentServerId == side.serverId;
      unawaited(side.dispose(sayLeft: !stillThere));
    }

    if (_callSide == null && wanted != null) {
      final user = wanted.user;
      if (user == null || wanted.supabaseKey == null) return;
      _callSide = _CallSide(
        realtime: _session.realtime,
        server: wanted,
        userId: user.id,
        displayName: user.displayName,
        // Taken over from the selected side, whose join already carries our
        // entry. Publishing it again would spend presence's small ration
        // on every switch for nothing.
        inherited: _currentServerId == wanted.id && _tracked,
      );
    }
    _callSide?.announce(_placeOn(_callSide!.serverId, _callSide!.userId));
  }

  /// Where we are on [serverId] as [VoiceBroadcast.announce] takes it: the
  /// call's channel when the call is on that server, else nowhere.
  ({String? channelId, bool sharing}) _placeOn(String serverId, String userId);

  Future<void> _closeCallSide() async {
    final side = _callSide;
    _callSide = null;
    await side?.dispose(sayLeft: true);
  }
}

/// The call's server's two joins, held while it is not the selected one.
class _CallSide {
  final String serverId;
  final String userId;
  final String _displayName;
  RealtimeLease? _presence;
  VoiceBroadcast? _voice;

  /// Whether the next `subscribed` is the join we took over rather than a
  /// new one, whose entry is already there.
  bool _inherited;

  /// Whether our entry is on this join, as far as we know: taken over with
  /// it, or published since.
  bool get tracked => _tracked;
  bool _tracked;

  _CallSide({
    required ServerRealtime realtime,
    required Server server,
    required this.userId,
    required String displayName,
    required bool inherited,
  }) : serverId = server.id,
       _displayName = displayName,
       _inherited = inherited,
       _tracked = inherited {
    _presence = realtime.join(
      server,
      'presence:${server.id}',
      // A reconnect drops the entry and rejoining does not bring it back, so
      // every subscribe after the first puts it there again.
      onStatus: (status) {
        if (status != RealtimeSubscribeStatus.subscribed) return;
        if (_inherited) {
          _inherited = false;
          return;
        }
        unawaited(_track());
      },
    );
    _voice = VoiceBroadcast(
      realtime: realtime,
      server: server,
      userId: userId,
      // Nothing here draws the server's calls; only ours is said.
      fetchRoster: () async => null,
      onChanged: () {},
    );
  }

  Future<void> _track() async {
    _tracked = false;
    try {
      final result = await _presence?.channel.track({
        'userId': userId,
        'displayName': _displayName,
      });
      _tracked = result == ChannelResponse.ok;
    } catch (_) {}
  }

  void announce(({String? channelId, bool sharing}) place) =>
      _voice?.announce(place.channelId, sharing: place.sharing);

  Future<void> dispose({required bool sayLeft}) async {
    final voice = _voice;
    final presence = _presence;
    _voice = null;
    _presence = null;
    if (sayLeft) voice?.announce(null);
    await voice?.dispose();
    await presence?.release();
  }
}
