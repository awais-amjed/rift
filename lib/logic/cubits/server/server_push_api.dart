part of 'server_cubit.dart';

/// Push notifications for a self-hosted server: registering this device, and
/// (for an admin) turning the whole thing on.
///
/// A server cannot wake a phone by itself. An FCM registration token is scoped
/// to the Firebase project the *app* was built against — Rift's — so waking a
/// Rift install needs Rift's credentials, which an operator does not have and
/// must not be given. So the ring is relayed: the admin enrols a credential on
/// central, writes it into their own server, and from then on that server's
/// triggers ask central to forward. Central learns a device token and a
/// moment, and nothing else; the push itself carries nothing at all.
///
/// That is why this mixin talks to two places at once, which is otherwise not
/// something a server call does.
mixin _ServerPushApiMixin on Cubit<ServerState> {
  ServerRepository get _repository;
  WakeIndexWriter get _wakeIndex;
  CentralDmRepository get _central;
  Server? _target(String? serverId);
  String _noTarget(String? serverId);
  Future<APIResponse> _callFor(
    Server server,
    Future<APIResponse> Function(String token) call,
  );

  /// How long to wait for the relay to say it is alive before giving up on it.
  static const _probeTimeout = Duration(seconds: 8);

  /// Whether the relay is reachable at all.
  ///
  /// Checked before writing the address into a server, because the address is
  /// compiled into the app and the thing behind it can move. A relay that has
  /// been repointed and not yet re-pointed *back* would otherwise be a server
  /// that quietly stops waking anyone — the failure would show up as missing
  /// notifications days later, which is the worst way to learn it.
  Future<bool> _relayAlive() async {
    try {
      final response = await http
          .get(Uri.parse(SupabaseConfig.pushRelayEndpoint))
          .timeout(_probeTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────
  // What the isolate wakes up into
  // ──────────────────────────────────────────────────────────

  /// Leave the push background isolate a snapshot of the server list.
  ///
  /// It is woken into a process that shares nothing with this one — no cubits,
  /// no hydrated storage — and cannot ask which servers this device is on. So
  /// the app writes it down. Only the fields a wake actually reads, and only
  /// when one of them has changed: the state emits on every token refresh and
  /// every selection, and neither is news to a sleeping isolate.
  ///
  /// Takes the state rather than reading it: `onChange` runs *before* the new
  /// state is installed, so the field would still hold the old list.
  void refreshWakeIndex(ServerState current) {
    if (!PushService.isSupported) return;
    unawaited(
      _wakeIndex.update(
        WakeIndex(
          servers: [
            for (final server in current.servers)
              if (server.user != null)
                WakeServer(
                  id: server.id,
                  name: server.name,
                  supabaseUrl: server.supabaseUrl,
                  anonKey: server.supabaseKey ?? '',
                  userId: server.user!.id,
                  username: server.user!.username,
                  keyVersion: server.keyVersion,
                  channels: {
                    for (final channel in server.channels)
                      channel.id: channel.name,
                  },
                ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // This device
  // ──────────────────────────────────────────────────────────

  /// Tell every joined server that this device can be woken.
  ///
  /// Runs on whatever token FCM has handed over, and again each time it
  /// rotates. Registration is unconditional — a server with push switched off
  /// simply keeps the row — because the alternative is that enabling push
  /// works for whoever signs in next and for nobody who was already there.
  Future<void> registerPushDevices() async {
    if (!PushService.isSupported) return;
    final token = PushService.instance.token.value;
    if (token == null) return;

    for (final server in state.servers) {
      await _callFor(
        server,
        (bearer) => _repository.registerDevice(
          server.supabaseUrl,
          anonKey: server.supabaseKey ?? '',
          bearerToken: bearer,
          token: token,
          platform: PushService.platform,
        ),
      );
    }
  }

  /// Give up this device's registration on one server — on leaving it, so the
  /// phone stops being woken for a place it is no longer in.
  ///
  /// Best-effort and deliberately not awaited by its caller: leaving must not
  /// wait on, or fail because of, a server that has already stopped answering.
  Future<void> forgetPushDevice(String serverId) async {
    if (!PushService.isSupported) return;
    final token = PushService.instance.token.value;
    final server = _target(serverId);
    if (token == null || server == null) return;

    await _callFor(
      server,
      (bearer) => _repository.unregisterDevice(
        server.supabaseUrl,
        anonKey: server.supabaseKey ?? '',
        bearerToken: bearer,
        token: token,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // The server (admin)
  // ──────────────────────────────────────────────────────────

  /// Whether this server can currently ring its members' phones.
  /// Returns `{enabled, relay_id}` — the id, never the secret.
  Future<APIResponse> pushStatus({String? serverId}) async {
    final server = _target(serverId);
    if (server == null) return APIResponse.error(_noTarget(serverId));
    return _callFor(
      server,
      (bearer) =>
          _repository.pushStatus(server.supabaseUrl, bearerToken: bearer),
    );
  }

  /// Turn push on: mint a relay credential on central, then hand it to the
  /// server, then register this device so it works without a restart.
  ///
  /// If the second step fails the credential is revoked again. Leaving a
  /// minted-but-unused credential behind would spend one of the small number
  /// an account may hold, and a few failed attempts would then look like a
  /// limit on how many servers somebody may run.
  Future<APIResponse> enablePush({String? serverId}) async {
    final server = _target(serverId);
    if (server == null) return APIResponse.error(_noTarget(serverId));

    if (!await _relayAlive()) {
      return APIResponse.error(
        'The notification relay at ${Uri.parse(SupabaseConfig.pushRelayEndpoint).host} '
        "isn't answering, so this server would have nowhere to send its pings. "
        'Try again in a moment.',
      );
    }

    final enrolled = await _central.enrollPushRelay(
      supabaseUrl: server.supabaseUrl,
      serverId: server.id,
      label: server.name,
    );
    if (!enrolled.success) return enrolled;

    final credential = enrolled.data as Map<String, dynamic>?;
    final relayId = credential?['relay_id'] as String?;
    final secret = credential?['secret'] as String?;
    if (relayId == null || secret == null) {
      return APIResponse.error('Central returned no relay credential');
    }

    final configured = await _callFor(
      server,
      (bearer) => _repository.configurePush(
        server.supabaseUrl,
        bearerToken: bearer,
        endpoint: SupabaseConfig.pushRelayEndpoint,
        relayId: relayId,
        secret: secret,
      ),
    );
    if (!configured.success) {
      unawaited(_central.revokePushRelay(relayId));
      return configured;
    }

    unawaited(registerPushDevices());
    return configured;
  }

  /// Turn push off, and give the credential back.
  ///
  /// Dropping the server's copy already makes it unusable — nothing else holds
  /// the secret — so the revoke is about the slot rather than about safety,
  /// and a failure to reach central is not a reason to report that push is
  /// still on.
  Future<APIResponse> disablePush({String? serverId}) async {
    final server = _target(serverId);
    if (server == null) return APIResponse.error(_noTarget(serverId));

    final result = await _callFor(
      server,
      (bearer) =>
          _repository.disablePush(server.supabaseUrl, bearerToken: bearer),
    );
    if (!result.success) return result;

    final relayId = (result.data as Map<String, dynamic>?)?['relay_id'];
    if (relayId is String) unawaited(_central.revokePushRelay(relayId));
    return result;
  }
}
