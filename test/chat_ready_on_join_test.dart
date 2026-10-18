import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_user.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift/data/enums/auth_status.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';
import 'package:rift/logic/cubits/channel_chat/channel_chat_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/logic/services/message_cache.dart';

/// Joining a server published no chat key until the app was started again.
///
/// The join changes the server list, and that sets off two readiness runs back
/// to back: the chat cubit's own, still showing no server, and the one
/// `ServerHub` starts by showing the new server. The first cleared the ready
/// mark once its teardown finished, which was in the middle of the second's —
/// so the second stood down as if a newer run had replaced it. Nobody could
/// seal the new member a channel key, and a call they went straight to sat on
/// "Waiting for this channel's key".

/// A server that answers every call this test reaches, counting key publishes.
class _Servers extends ServerRepository {
  int publishes = 0;

  @override
  Future<APIResponse> publishChatKey(
    String supabaseUrl, {
    required String anonKey,
    required String userId,
    String? bearerToken,
    required String chatPublicKey,
  }) async {
    publishes++;
    return APIResponse.success(const {
      'published': true,
      publishedChatKeyIsNew: true,
    });
  }

  @override
  Future<APIResponse> sweepChannelKeys(
    String supabaseUrl, {
    String? bearerToken,
  }) async => APIResponse.success(const {'work': [], 'more': false});

  @override
  Future<APIResponse> sweepAttachments(
    String supabaseUrl, {
    String? bearerToken,
  }) async => APIResponse.success(const {});
}

/// An unlocked vault, without secure storage.
class _Vault extends VaultCubit {
  _Vault() {
    emit(
      VaultState(
        status: AuthStatus.unlocked,
        masterSeed: base64Encode(List.filled(32, 7)),
      ),
    );
  }
}

/// No anon key, so nothing here opens a socket.
final _joined = Server(
  id: 'srv',
  name: 'Lighthouse',
  supabaseUrl: 'https://srv.invalid',
  token: 'token',
  tokenIssuedAt: DateTime.now(),
  user: const ServerUser(
    id: 'me',
    username: 'me',
    displayName: 'Me',
    permissions: UserPermissions(),
  ),
);

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('joining a server publishes our chat key there', () async {
    final servers = _Servers();
    final session = SessionRepository(servers: servers);
    final cache = Directory.systemTemp.createTempSync('rift_cache');
    final chat = ChannelChatCubit(
      session: session,
      vaultCubit: _Vault(),
      messageCache: MessageCache(root: () async => cache),
    );
    // What `ServerHub` does, and in its order: it subscribes after the chat
    // cubit, so the cubit's own run starts first.
    final hub = session.changes.listen(
      (_) => chat.showServer(session.selectedServer?.id),
    );
    await _settle();

    session.publish(servers: [_joined], selectedServerId: _joined.id);
    await _settle();

    expect(servers.publishes, 1);

    await hub.cancel();
    await chat.close();
    await session.dispose();
    cache.deleteSync(recursive: true);
  });
}
