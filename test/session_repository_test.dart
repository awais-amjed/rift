import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/api_response.dart';
import 'package:rift/data/classes/server.dart';
import 'package:rift/data/classes/server_details.dart';
import 'package:rift/data/enums/error_code.dart';
import 'package:rift/data/repositories/server_repository.dart';
import 'package:rift/data/repositories/session_repository.dart';

/// A session whose sign-in answers at once, counting how often it is asked.
class _CountingSession extends SessionRepository {
  int signIns = 0;
  String? next = 'fresh';

  @override
  Future<({String? token, ServerDetails? details, String? error})> login(
    Server server,
  ) async {
    signIns++;
    await Future<void>.delayed(Duration.zero);
    final token = next;
    if (token == null) return (token: null, details: null, error: 'refused');
    return (
      token: token,
      details: ServerDetails.fromJson(const {}),
      error: null,
    );
  }
}

/// A server whose details read answers with [reply].
class _DetailsServers extends ServerRepository {
  APIResponse reply = APIResponse.success(const {'name': 'Renamed'});

  @override
  Future<APIResponse> getServerDetails(
    String supabaseUrl, {
    required String anonKey,
    String? bearerToken,
  }) async => reply;
}

Server _server({String token = 'old'}) => Server(
  id: 's1',
  name: 'Test',
  supabaseUrl: 'https://server.invalid',
  token: token,
);

APIResponse _expired() =>
    APIResponse.error('expired', errorCode: ErrorCode.tokenExpired);

void main() {
  test(
    'a call refused for its session signs in again and retries once',
    () async {
      final session = _CountingSession();
      session.publish(servers: [_server()], selectedServerId: 's1');
      final tokens = <String>[];

      final response = await session.callSelected((token) async {
        tokens.add(token);
        return token == 'fresh' ? APIResponse.success('ok') : _expired();
      });

      expect(response.success, isTrue);
      expect(tokens, ['old', 'fresh']);
      expect(session.signIns, 1);
    },
  );

  test('a failed re-login hands back the refusal without retrying', () async {
    final session = _CountingSession()..next = null;
    session.publish(servers: [_server()], selectedServerId: 's1');
    var calls = 0;

    final response = await session.callSelected((_) async {
      calls++;
      return _expired();
    });

    expect(response.success, isFalse);
    expect(calls, 1);
  });

  test('concurrent re-logins for one server share a single sign-in', () async {
    final session = _CountingSession();
    session.publish(servers: [_server()], selectedServerId: 's1');

    final tokens = await Future.wait([
      session.reAuthenticate('s1'),
      session.reAuthenticate('s1'),
    ]);

    expect(tokens, ['fresh', 'fresh']);
    expect(session.signIns, 1);
  });

  test('a new token is announced before the re-login answers', () async {
    final session = _CountingSession();
    session.publish(servers: [_server()], selectedServerId: 's1');
    // What ServerCubit does with it: write it onto the server.
    session.logins.listen((login) {
      session.publish(
        servers: [_server(token: login.token)],
        selectedServerId: 's1',
      );
    });

    await session.reAuthenticate('s1');

    expect(session.selectedServer?.token, 'fresh');
  });

  test('a named server is the target, not the selection', () {
    final session = _CountingSession();
    final other = Server(
      id: 's2',
      name: 'Other',
      supabaseUrl: 'https://other.invalid',
      token: 'other',
    );
    session.publish(servers: [_server(), other], selectedServerId: 's1');

    expect(session.target('s2')?.id, 's2');
    expect(session.target(null)?.id, 's1');
    expect(session.target('gone'), isNull);
  });

  test('no server selected fails without calling anything', () async {
    final session = _CountingSession();
    var calls = 0;

    final response = await session.callSelected((_) async {
      calls++;
      return APIResponse.success(null);
    });

    expect(response.success, isFalse);
    expect(calls, 0);
  });

  test('a re-read after a write is announced before it answers', () async {
    final session = SessionRepository(servers: _DetailsServers());
    session.publish(servers: [_server()], selectedServerId: 's1');
    final heard = <SessionDetails>[];
    session.details.listen(heard.add);

    final ok = await session.refreshDetails(_server());

    expect(ok, isTrue);
    expect(heard.single.serverId, 's1');
    expect(heard.single.details.name, 'Renamed');
  });

  test('a failed re-read announces nothing', () async {
    final servers = _DetailsServers()..reply = APIResponse.error('down');
    final session = SessionRepository(servers: servers);
    session.publish(servers: [_server()], selectedServerId: 's1');
    final heard = <SessionDetails>[];
    session.details.listen(heard.add);

    expect(await session.refreshDetails(_server()), isFalse);
    expect(heard, isEmpty);
  });

  test('a missing server is told apart from no selection', () {
    final session = SessionRepository(servers: _DetailsServers());
    expect(session.noTarget(null), 'No server selected');
    expect(session.noTarget('gone'), contains('no longer on this device'));
  });
}
