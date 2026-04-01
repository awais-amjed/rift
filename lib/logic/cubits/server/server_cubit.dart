import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../data/classes/channel.dart';
import '../../../data/classes/server.dart';
import '../../../data/classes/server_user.dart';
import '../../../data/repositories/server_repository.dart';

part 'server_cubit.g.dart';

part 'server_state.dart';

class ServerCubit extends HydratedCubit<ServerState> {
  final ServerRepository _repository = ServerRepository();

  ServerCubit() : super(const ServerState());

  // ──────────────────────────────────────────────────────────
  // Server selection
  // ──────────────────────────────────────────────────────────

  void setSelectedServer(Server? server) {
    emit(
      state.copyWith(
        selectedServerId: server?.id,
        clearSelectedServerId: server == null,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  // CRUD
  // ──────────────────────────────────────────────────────────

  Server addServer(
    String supabaseUrl,
    String token,
    Map<String, dynamic> serverDetails,
  ) {
    final newServer = Server.fromJoin(supabaseUrl, token, serverDetails);
    final updated = [...state.servers, newServer];
    emit(state.copyWith(servers: updated, selectedServerId: newServer.id));
    return newServer;
  }

  Server addCreatedServer(
    String supabaseUrl,
    Map<String, dynamic> serverData,
    String token,
  ) {
    final newServer = Server.fromCreate(supabaseUrl, serverData, token);
    final updated = [...state.servers, newServer];
    emit(state.copyWith(servers: updated, selectedServerId: newServer.id));
    return newServer;
  }

  void removeServer(String serverId) {
    final updated = state.servers.where((s) => s.id != serverId).toList();
    String? newSelectedId = state.selectedServerId;
    if (newSelectedId == serverId) {
      newSelectedId = updated.isNotEmpty ? updated.first.id : null;
    }
    emit(
      state.copyWith(
        servers: updated,
        selectedServerId: newSelectedId,
        clearSelectedServerId: newSelectedId == null,
      ),
    );
  }

  void updateServer(
    String serverId, {
    String? name,
    String? iconUrl,
    String? supabaseKey,
    String? livekitUrl,
    String? token,
    String? keyVersion,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  }) {
    final updated = state.servers.map((s) {
      if (s.id != serverId) return s;
      return s.copyWith(
        name: name,
        iconUrl: iconUrl,
        supabaseKey: supabaseKey,
        livekitUrl: livekitUrl,
        token: token,
        keyVersion: keyVersion,
        user: user,
        channels: channels,
        clearUser: clearUser,
      );
    }).toList();
    emit(state.copyWith(servers: updated));
  }

  // ──────────────────────────────────────────────────────────
  // API Operations
  // ──────────────────────────────────────────────────────────

  /// Create an invite code for the selected server.
  Future<({bool success, String? inviteCode, String? error})> createInvite({
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
    int? maxUses = 1,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, inviteCode: null, error: 'No server selected');
    }

    final response = await _repository.createInvite(
      server.supabaseUrl,
      server.token,
      isServerAdmin: isServerAdmin,
      isChannelManager: isChannelManager,
      canCreateTokens: canCreateTokens,
      maxUses: maxUses,
    );

    if (response.success) {
      final inviteCode = response.data['invite_code'] as String;
      return (success: true, inviteCode: inviteCode, error: null);
    } else {
      return (
        success: false,
        inviteCode: null,
        error: response.error ?? 'Failed to generate invite',
      );
    }
  }

  /// Register on a server using an invite code + cryptographic identity.
  /// Used for both initial server setup (admin) and joining via invite.
  Future<({bool success, String? error})> createUserAccount({
    required String supabaseUrl,
    required String inviteCode,
    required String username,
    required String displayName,
    required String publicKey,
    required String stableId,
  }) async {
    final response = await _repository.register(
      supabaseUrl,
      inviteCode: inviteCode,
      publicKey: publicKey,
      stableId: stableId,
      username: username,
      displayName: displayName,
    );

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to register',
      );
    }

    // register returns full server context with a new auth token
    final data = response.data as Map<String, dynamic>;
    final token = data['token'] as String;

    addServer(supabaseUrl, token, data);

    return (success: true, error: null);
  }

  /// Validate an invite code — looks up the invite on the server,
  /// does NOT create a user yet.
  Future<
    ({
      bool success,
      String? error,
      String? serverId,
      String? serverName,
    })
  >
  validateInvite(String supabaseUrl, String inviteCode) async {
    // For now, we can't validate without registering.
    // The client will call register directly with the invite code.
    // This is a placeholder for future invite preview functionality.
    return (
      success: true,
      error: null,
      serverId: null,
      serverName: null,
    );
  }

  /// Create a new channel in the selected server.
  Future<({bool success, String? error})> createChannel({
    required String name,
    required String channelType,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _repository.createChannel(
      server.supabaseUrl,
      server.token,
      name: name,
      channelType: channelType,
    );

    if (!response.success) {
      return (success: false, error: response.error ?? 'Failed to create channel');
    }

    // Refresh channels to pick up the newly created one.
    await refreshServerDetails();
    return (success: true, error: null);
  }

  /// Refresh the channel list and other details for the selected server.
  Future<({bool success, String? error})> refreshServerDetails() async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final response = await _repository.getServerDetails(
      server.supabaseUrl,
      server.token,
    );

    if (response.success) {
      final data = response.data as Map<String, dynamic>;
      final rawChannels = data['channels'] as List<dynamic>?;
      final channels =
          rawChannels
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];
      final supabaseKey = data['supabase_key'] as String?;
      final rawUser = data['user'];
      final user =
          rawUser != null
              ? ServerUser.fromJson(rawUser as Map<String, dynamic>)
              : null;

      updateServer(
        server.id,
        channels: channels,
        supabaseKey: supabaseKey,
        user: user,
      );
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to refresh server details',
      );
    }
  }

  // ──────────────────────────────────────────────────────────
  // Hydration
  // ──────────────────────────────────────────────────────────

  @override
  ServerState? fromJson(Map<String, dynamic> json) =>
      ServerState.fromJson(json);

  @override
  Map<String, dynamic>? toJson(ServerState state) => state.toJson();
}
