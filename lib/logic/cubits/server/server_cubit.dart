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
    String? livekitUrl,
    ServerUser? user,
    List<Channel>? channels,
    bool clearUser = false,
  }) {
    final updated = state.servers.map((s) {
      if (s.id != serverId) return s;
      return s.copyWith(
        name: name,
        iconUrl: iconUrl,
        livekitUrl: livekitUrl,
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

  /// Create an access/invite token for the selected server.
  Future<({bool success, String? token, String? error})> createAccessToken({
    bool isServerAdmin = false,
    bool isChannelManager = false,
    bool canCreateTokens = false,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, token: null, error: 'No server selected');
    }

    final response = await _repository.createAccessToken(
      server.supabaseUrl,
      server.token,
      isServerAdmin: isServerAdmin,
      isChannelManager: isChannelManager,
      canCreateTokens: canCreateTokens,
    );

    if (response.success) {
      final token = response.data['token'] as String;
      return (success: true, token: token, error: null);
    } else {
      return (
        success: false,
        token: null,
        error: response.error ?? 'Failed to generate invite token',
      );
    }
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

    if (response.success) {
      // Refresh server details to get updated channel list
      await refreshServerDetails();
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: response.error ?? 'Failed to create channel',
      );
    }
  }

  /// Create a user account for the selected server.
  Future<({bool success, String? error})> createUserAccount({
    required String username,
    required String displayName,
  }) async {
    final server = state.selectedServer;
    if (server == null) {
      return (success: false, error: 'No server selected');
    }

    final joinResponse = await _repository.joinServer(
      server.supabaseUrl,
      server.token,
      username: username,
      displayName: displayName,
    );

    if (!joinResponse.success) {
      return (
        success: false,
        error: joinResponse.error ?? 'Failed to create account',
      );
    }

    // Fetch refreshed server details to get the user data
    final detailsResponse = await _repository.getServerDetails(
      server.supabaseUrl,
      server.token,
    );

    if (detailsResponse.success) {
      final rawUser = detailsResponse.data['user'];
      if (rawUser != null) {
        updateServer(
          server.id,
          user: ServerUser.fromJson(rawUser as Map<String, dynamic>),
        );
      }
      return (success: true, error: null);
    } else {
      return (
        success: false,
        error: detailsResponse.error ?? 'Failed to fetch user details',
      );
    }
  }

  /// Validate token and join server. Returns server details and whether user exists.
  Future<
    ({
      bool success,
      String? error,
      Map<String, dynamic>? serverDetails,
      bool userExists,
    })
  >
  validateAndJoinServer(String supabaseUrl, String token) async {
    final response = await _repository.getServerDetails(supabaseUrl, token);

    if (!response.success) {
      return (
        success: false,
        error: response.error ?? 'Failed to connect to server',
        serverDetails: null,
        userExists: false,
      );
    }

    final serverData = response.data as Map<String, dynamic>;
    final user = serverData['user'];
    final userExists = user != null;

    // Always add the server so it becomes the selected server.
    // If the user doesn't exist yet, createUserAccount can still find it.
    addServer(supabaseUrl, token, serverData);

    return (
      success: true,
      error: null,
      serverDetails: serverData,
      userExists: userExists,
    );
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
      final rawChannels = response.data['channels'] as List<dynamic>?;
      final channels =
          rawChannels
              ?.map((c) => Channel.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [];

      updateServer(server.id, channels: channels);
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
