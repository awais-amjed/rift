import 'package:flutter_test/flutter_test.dart';
import 'package:rift_crypto/rift_crypto.dart';

void main() {
  const aKey = 'QUJDREVGR0hJSktMTU5PUFFSU1RVVldYWVphYmNkZWY=';
  const bKey = 'MTIzNDU2Nzg5MEFCQ0RFRkdISUpLTE1OT1BRUlNUVVY=';
  const aId = '11111111-1111-1111-1111-111111111111';
  const bId = '22222222-2222-2222-2222-222222222222';

  String forPair(String k1, String i1, String k2, String i2) =>
      SafetyCode.between(myKey: k1, myId: i1, theirKey: k2, theirId: i2);

  test('both devices compute the same sixty digits', () {
    final mine = forPair(aKey, aId, bKey, bId);
    final theirs = forPair(bKey, bId, aKey, aId);
    expect(mine, theirs);
    expect(mine.length, 60);
    expect(RegExp(r'^\d{60}$').hasMatch(mine), isTrue);
  });

  test('a different key gives a different code', () {
    const other = 'Zm9yZ2VkLWtleS1mb3ItdGVzdGluZy1vbmx5LTEyMzQ1Ng==';
    expect(
      forPair(aKey, aId, other, bId),
      isNot(forPair(aKey, aId, bKey, bId)),
    );
  });

  test('the same key under another id gives a different code', () {
    expect(forPair(aKey, aId, bKey, bId), isNot(forPair(aKey, aId, bKey, aId)));
  });

  test('it reads in groups of five', () {
    final groups = SafetyCode.groups(forPair(aKey, aId, bKey, bId));
    expect(groups.length, 12);
    expect(groups.every((g) => g.length == 5), isTrue);
  });

  test('the QR payload names its version', () {
    expect(SafetyCode.qrPayload('123'), 'rift:safety:1:123');
  });
}
