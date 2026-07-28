import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/repositories/crypto_repository.dart';

void main() {
  final crypto = CryptoRepository();

  // Fixed seed so derivations are reproducible across runs.
  final seed = Uint8List.fromList(List<int>.generate(32, (i) => i));

  group('deriveServerIdentity', () {
    test('is deterministic for the same (seed, host, serverId)', () async {
      final a = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'a.example.com',
        serverId: 's1',
      );
      final b = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'a.example.com',
        serverId: 's1',
      );

      expect(a.publicKeyBase64, b.publicKeyBase64);
      expect(a.stableId, b.stableId);
    });

    test('same host, different serverId → distinct identity '
        '(the multi-server-per-project guarantee)', () async {
      final s1 = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'shared.example.com',
        serverId: 's1',
      );
      final s2 = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'shared.example.com',
        serverId: 's2',
      );

      expect(s1.publicKeyBase64, isNot(s2.publicKeyBase64));
      expect(s1.stableId, isNot(s2.stableId));
    });

    test('different host → distinct identity', () async {
      final a = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'a.example.com',
        serverId: 's1',
      );
      final b = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'b.example.com',
        serverId: 's1',
      );

      expect(a.publicKeyBase64, isNot(b.publicKeyBase64));
      expect(a.stableId, isNot(b.stableId));
    });

    test('central (serverId null) differs from any server on the same host, '
        'and is stable', () async {
      final central1 = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'h.example.com',
      );
      final central2 = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'h.example.com',
      );
      final server = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'h.example.com',
        serverId: 's1',
      );

      expect(central1.publicKeyBase64, central2.publicKeyBase64); // unchanged
      expect(central1.publicKeyBase64, isNot(server.publicKeyBase64));
    });

    test('different seed → distinct identity', () async {
      final otherSeed = Uint8List.fromList(
        List<int>.generate(32, (i) => 31 - i),
      );
      final a = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'h',
        serverId: 's1',
      );
      final b = await crypto.deriveServerIdentity(
        masterSeed: otherSeed,
        host: 'h',
        serverId: 's1',
      );

      expect(a.publicKeyBase64, isNot(b.publicKeyBase64));
    });

    test('public key is 32 bytes (Ed25519)', () async {
      final id = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'h',
        serverId: 's1',
      );
      expect(id.publicKeyBytes.length, 32);
    });
  });

  group('signSiws', () {
    test('produces a well-formed SIWS message that verifies', () async {
      final id = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'localhost',
        serverId: 's1',
      );
      final address = CryptoRepository.toBase58(id.publicKeyBytes);

      final signed = await crypto.signSiws(
        keyPair: id.keyPair,
        publicKeyBytes: id.publicKeyBytes,
        domain: 'localhost',
        uri: 'http://localhost:8000',
      );

      // Format required by GoTrue's web3 grant (verified on the stack).
      expect(
        signed.message,
        startsWith('localhost wants you to sign in with your Solana account:'),
      );
      expect(signed.message, contains('\n$address\n'));
      expect(signed.message, contains('URI: http://localhost:8000'));
      expect(signed.message, contains('Chain ID: solana:mainnet'));
      expect(signed.message, contains('Version: 1'));

      // The signature must verify against the derived public key.
      final ed = Ed25519();
      final publicKey = await id.keyPair.extractPublicKey();
      final ok = await ed.verify(
        utf8.encode(signed.message),
        signature: Signature(
          base64Decode(signed.signatureBase64),
          publicKey: publicKey,
        ),
      );
      expect(ok, isTrue);
    });

    test('a tampered message fails verification', () async {
      final id = await crypto.deriveServerIdentity(
        masterSeed: seed,
        host: 'localhost',
        serverId: 's1',
      );
      final signed = await crypto.signSiws(
        keyPair: id.keyPair,
        publicKeyBytes: id.publicKeyBytes,
        domain: 'localhost',
        uri: 'http://localhost:8000',
      );

      final ed = Ed25519();
      final publicKey = await id.keyPair.extractPublicKey();
      final ok = await ed.verify(
        utf8.encode('${signed.message}tampered'),
        signature: Signature(
          base64Decode(signed.signatureBase64),
          publicKey: publicKey,
        ),
      );
      expect(ok, isFalse);
    });
  });

  group('encoding helpers', () {
    test('base64 round-trips', () {
      final bytes = Uint8List.fromList([0, 1, 2, 250, 255]);
      expect(
        CryptoRepository.fromBase64(CryptoRepository.toBase64(bytes)),
        bytes,
      );
    });

    test('base58 preserves leading zeros as "1"s', () {
      expect(CryptoRepository.toBase58(Uint8List.fromList([0, 0, 0])), '111');
      expect(
        CryptoRepository.toBase58(Uint8List.fromList([0, 0, 1])),
        startsWith('11'),
      );
    });

    test('base58 uses only the base58 alphabet (no 0 O I l)', () {
      final s = CryptoRepository.toBase58(
        Uint8List.fromList(List<int>.generate(32, (i) => (i * 7) & 0xff)),
      );
      expect(s, matches(RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$')));
    });
  });
}
