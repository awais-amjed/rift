import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/reaction_echoes.dart';

void main() {
  test('each toggle lets one ring of ours go, and no more', () {
    final echoes = ReactionEchoes();
    expect(echoes.take('5'), isFalse);
    echoes
      ..expect('5')
      ..expect('5');
    expect(echoes.take('6'), isFalse);
    expect(echoes.take('5'), isTrue);
    expect(echoes.take('5'), isTrue);
    expect(echoes.take('5'), isFalse);
  });

  test('what is owed lapses, in case its ring was lost', () {
    var now = DateTime(2026, 11, 26);
    final echoes = ReactionEchoes(now: () => now)..expect('5');
    now = now.add(const Duration(seconds: 5));
    expect(echoes.take('5'), isFalse);
  });
}
