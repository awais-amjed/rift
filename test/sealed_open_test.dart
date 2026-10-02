import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/sealed_open.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// "Cannot read it" and "must not show it" — ARCHITECTURE.md §4. A DM went
/// empty when the other person's key changed, because a message that verified
/// and then did not open under the new DM key was dropped like a forgery.
void main() {
  final crypto = CryptoRepository();
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  Future<({ServerIdentity id, MessageEnvelope envelope, Uint8List key})>
  sealed() async {
    final id = await crypto.deriveServerIdentity(
      masterSeed: seed,
      host: 'h',
      serverId: 's1',
    );
    final key = crypto.generateChannelKey();
    final envelope = await crypto.sealMessage(
      plaintext: 'hello',
      messageKey: key,
      signingKeyPair: id.keyPair,
      contextId: 'dm:a:b',
      keyVersion: 1,
    );
    return (id: id, envelope: envelope, key: key);
  }

  test('the right key opens it', () async {
    final s = await sealed();
    final opened = await openSealed(
      crypto,
      envelope: s.envelope,
      messageKey: s.key,
      senderPublicKey: s.id.publicKeyBytes,
      contextId: 'dm:a:b',
    );
    expect(opened.outcome, SealedOutcome.opened);
    expect(opened.plaintext, 'hello');
  });

  test('a genuine message under the wrong key is locked', () async {
    final s = await sealed();
    final opened = await openSealed(
      crypto,
      envelope: s.envelope,
      messageKey: crypto.generateChannelKey(),
      senderPublicKey: s.id.publicKeyBytes,
      contextId: 'dm:a:b',
    );
    expect(opened.outcome, SealedOutcome.locked);
    expect(opened.plaintext, isNull);
  });

  test('a bad signature is dropped, whatever the key', () async {
    final s = await sealed();
    final other = await crypto.deriveServerIdentity(
      masterSeed: seed,
      host: 'h',
      serverId: 's2',
    );
    for (final key in [s.key, crypto.generateChannelKey()]) {
      final opened = await openSealed(
        crypto,
        envelope: s.envelope,
        messageKey: key,
        senderPublicKey: other.publicKeyBytes,
        contextId: 'dm:a:b',
      );
      expect(opened.outcome, SealedOutcome.dropped);
    }
  });

  test('a message replayed into another conversation is dropped', () async {
    final s = await sealed();
    final opened = await openSealed(
      crypto,
      envelope: s.envelope,
      messageKey: crypto.generateChannelKey(),
      senderPublicKey: s.id.publicKeyBytes,
      contextId: 'dm:a:c',
    );
    expect(opened.outcome, SealedOutcome.dropped);
  });
}
