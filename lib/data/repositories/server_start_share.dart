import '../classes/api_response.dart';
import '../classes/member_page.dart';
import '../enums/error_code.dart';
import 'server_db.dart';

/// What an app loads first on a server, asked once (`server_start`, self-host
/// 064).
///
/// Five features read their first answer from a server as it opens: the
/// unread counts, the member list, the soundboard, the bots that may listen
/// in each voice channel and the bots summoned there. They were five
/// requests for every server on the rail at every start. Each still asks for
/// its own, but with `first`, and the first of them to ask sends one
/// `server_start` that answers all five; the others, asking while it is out or
/// just back, take their part of it. Each part is handed out once, and only
/// within [_StartAnswer.freshFor] of its arrival, so nothing is drawn from an
/// answer older than a request of its own would have been. A read that is
/// not a first load — a ring, a retry — is always its own call.
///
/// A server older than 064 answers `PGRST202` once, and is asked the five
/// calls from then on.
///
/// An app opening after an hour away holds a token the server has stopped
/// taking. The refusal of the shared call is then each part's answer, so the
/// caller signs in once and asks again, and that retry, under the new token,
/// is one `server_start` again. Answered with nothing, each part asked for
/// itself with the old token, was refused, and its retry fell inside
/// [_startGap]: five calls refused and five more answered, at the start that
/// most needed one (seen live, Nov 26).
class ServerStartShare {
  final ServerDb _db;

  ServerStartShare(this._db);

  /// Servers, by URL, that have no `server_start`.
  final Set<String> _noStart = {};

  /// Servers, by URL, whose console sweeps attachments itself
  /// (`sweeps_itself`), so an app need not ask `sweep_attachments`.
  final Set<String> _sweepsItself = {};

  /// The answer being shared, by `'<url>|<token>'`: one caller's token is one
  /// member on one server, and the answer is theirs.
  final Map<String, _StartAnswer> _starts = {};

  /// When each server was last sent one, by URL. A first load that finds
  /// the last answer gone stale asks for itself rather than sending another
  /// for its one part, unless it has been [_startGap] since: a server's
  /// features open together, and one arriving on its own wants one answer.
  final Map<String, DateTime> _startSent = {};
  static const _startGap = Duration(seconds: 30);

  /// What `server_start` sends as `p_member_limit`, and the only sidebar
  /// limit an answer can stand in for: one row past a page (`Paging.split`).
  static const memberLimit = MemberPage.pageSize + 1;

  /// Part [name] of a shared first answer, or null when the caller should
  /// ask for it itself, or the refusal when the server would not take the
  /// caller's token, which the caller answers with.
  Future<dynamic> part(
    String supabaseUrl,
    String anonKey,
    String? bearerToken,
    String name,
  ) async {
    if (_noStart.contains(supabaseUrl)) return null;
    final key = '$supabaseUrl|$bearerToken';
    var answer = _starts[key];
    if (answer == null || !answer.mayServe) {
      final sent = _startSent[supabaseUrl];
      if (sent != null && DateTime.now().difference(sent) < _startGap) {
        return null;
      }
      // One a server at a time: an answer under a token since rotated, or
      // one gone stale, will not be wanted again.
      _starts.removeWhere((k, _) => k.startsWith('$supabaseUrl|'));
      _startSent[supabaseUrl] = DateTime.now();
      answer = _StartAnswer(_askStart(supabaseUrl, anonKey, bearerToken));
      _starts[key] = answer;
    }
    final response = await answer.future;
    if (ErrorCode.isSessionInvalid(response.errorCode)) return response;
    final data = response.data;
    if (!response.success || data is! Map<String, dynamic>) return null;
    if (!answer.take(name)) return null;
    return data[name];
  }

  /// Whether the server at [supabaseUrl] sweeps attachments itself, so an
  /// app opening it has no `sweep_attachments` to ask. Known once a
  /// `server_start` has answered; one still out is waited for. Never asked
  /// yet, it is not known, and the app asks as it always did.
  Future<bool> sweptByServer(String supabaseUrl) async {
    if (_sweepsItself.contains(supabaseUrl)) return true;
    if (_noStart.contains(supabaseUrl)) return false;
    final pending = [
      for (final entry in _starts.entries)
        if (entry.key.startsWith('$supabaseUrl|')) entry.value.future,
    ];
    await Future.wait(pending);
    return _sweepsItself.contains(supabaseUrl);
  }

  Future<APIResponse> _askStart(
    String supabaseUrl,
    String anonKey,
    String? bearerToken,
  ) async {
    final response = await ServerDb.run(() async {
      final db = _db.client(supabaseUrl, anonKey, bearerToken);
      return db.rpc('server_start', params: {'p_member_limit': memberLimit});
    });
    if (response.errorCode == 'PGRST202') _noStart.add(supabaseUrl);
    // The retry under a new token may ask again at once.
    if (ErrorCode.isSessionInvalid(response.errorCode)) {
      _startSent.remove(supabaseUrl);
    }
    final data = response.data;
    if (response.success &&
        data is Map<String, dynamic> &&
        data['sweeps_itself'] == true) {
      _sweepsItself.add(supabaseUrl);
    }
    return response;
  }
}

/// One `server_start` answer, while it may still be shared.
class _StartAnswer {
  /// How long after it arrives an answer may still stand in for a first
  /// load's own request. The features of a server opening ask within a few
  /// milliseconds of each other; one asking later reads for itself.
  static const freshFor = Duration(seconds: 1);

  _StartAnswer(Future<APIResponse> asked) {
    future = asked.whenComplete(() => _arrived = DateTime.now());
  }

  late final Future<APIResponse> future;
  DateTime? _arrived;
  final Set<String> _taken = {};

  /// Still out, or back within [freshFor].
  bool get mayServe {
    final arrived = _arrived;
    return arrived == null || DateTime.now().difference(arrived) <= freshFor;
  }

  /// Hand out [part], once.
  bool take(String part) => mayServe && _taken.add(part);
}
