import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rift/data/repositories/server_reach_probe.dart';

void main() {
  ServerReachProbe probe(Map<String, int?> answers) => ServerReachProbe(
    client: MockClient((request) async {
      final status = answers[request.url.toString()];
      if (status == null) throw http.ClientException('unreachable');
      return http.Response('', status);
    }),
  );

  test('any answer below 500 is a server reached', () async {
    expect(await probe({'https://a': 200}).anyAnswers(['https://a']), isTrue);
    // An old server with no status page.
    expect(await probe({'https://a': 404}).anyAnswers(['https://a']), isTrue);
  });

  test('a proxy saying it cannot get through is not a server', () async {
    // With Wi-Fi off, a local proxy answered 502 and the probe read online.
    for (final status in [502, 503, 504]) {
      expect(
        await probe({'https://a': status}).anyAnswers(['https://a']),
        isFalse,
        reason: '$status',
      );
    }
  });

  test('one server answering is enough', () async {
    final p = probe({'https://up': 200, 'https://down': null});
    expect(await p.anyAnswers(['https://down', 'https://up']), isTrue);
    expect(await p.anyAnswers(['https://down']), isFalse);
  });

  test('nobody to ask is no answer', () async {
    expect(await probe({}).anyAnswers(const []), isNull);
  });
}
