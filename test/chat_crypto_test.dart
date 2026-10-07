import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rift_crypto/rift_crypto.dart';

/// Exercises the E2E messaging crypto (ARCHITECTURE.md §4) end-to-end, in-process:
/// chat-identity derivation, the symmetric DM key, channel-key wrap/unwrap, and
/// the signed message envelope. These are the guarantees a server compromise
/// must not break, so each has a matching negative (tamper / forge / replay).
void main() {
  final crypto = CryptoRepository();

  // Two fixed seeds → two reproducible users (Alice, Bob).
  final aliceSeed = Uint8List.fromList(List<int>.generate(32, (i) => i));
  final bobSeed = Uint8List.fromList(List<int>.generate(32, (i) => 63 - i));

  group('deriveChatIdentity', () {
    test('is deterministic for the same (seed, host)', () async {
      final a = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final b = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      expect(a.publicKeyBase64, b.publicKeyBase64);
    });

    test('different host → distinct chat identity', () async {
      final a = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'a',
      );
      final b = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'b',
      );
      expect(a.publicKeyBase64, isNot(b.publicKeyBase64));
    });

    test('the X25519 chat key is domain-separated from the Ed25519 auth key '
        '(same seed+host must not yield the same public bytes)', () async {
      final chat = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final auth = await crypto.deriveServerIdentity(
        masterSeed: aliceSeed,
        host: 'h',
        serverId: 's1',
      );
      // Different curves and different HMAC context ("h:chat:v1" vs
      // "h:s1:v1") — the raw public bytes must not collide.
      expect(chat.publicKeyBytes, isNot(auth.publicKeyBytes));
    });

    test('public key is 32 bytes (X25519)', () async {
      final id = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      expect(id.publicKeyBytes.length, 32);
    });
  });

  group('deriveDmKey (Design 1)', () {
    test('both parties derive the same key (DH is commutative)', () async {
      final alice = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final bob = await crypto.deriveChatIdentity(
        masterSeed: bobSeed,
        host: 'h',
      );

      final keyAtoB = await crypto.deriveDmKey(
        myKeyPair: alice.keyPair,
        theirPublicKey: bob.publicKeyBytes,
      );
      final keyBtoA = await crypto.deriveDmKey(
        myKeyPair: bob.keyPair,
        theirPublicKey: alice.publicKeyBytes,
      );

      expect(keyAtoB, keyBtoA);
      expect(keyAtoB.length, 32);
    });

    test('a different peer yields a different DM key', () async {
      final alice = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final bob = await crypto.deriveChatIdentity(
        masterSeed: bobSeed,
        host: 'h',
      );
      final carolSeed = Uint8List.fromList(
        List<int>.generate(32, (i) => (i * 3) & 0xff),
      );
      final carol = await crypto.deriveChatIdentity(
        masterSeed: carolSeed,
        host: 'h',
      );

      final withBob = await crypto.deriveDmKey(
        myKeyPair: alice.keyPair,
        theirPublicKey: bob.publicKeyBytes,
      );
      final withCarol = await crypto.deriveDmKey(
        myKeyPair: alice.keyPair,
        theirPublicKey: carol.publicKeyBytes,
      );

      expect(withBob, isNot(withCarol));
    });
  });

  group('wrapKey / unwrapKey (Design 2 channel keyring)', () {
    test('the recipient recovers the exact channel key', () async {
      final bob = await crypto.deriveChatIdentity(
        masterSeed: bobSeed,
        host: 'h',
      );
      final channelKey = crypto.generateChannelKey();

      final wrapped = await crypto.wrapKey(
        key: channelKey,
        recipientPublicKey: bob.publicKeyBytes,
      );
      final unwrapped = await crypto.unwrapKey(
        wrapped: wrapped,
        myKeyPair: bob.keyPair,
      );

      expect(unwrapped, channelKey);
    });

    test('a non-recipient cannot unwrap (AES-GCM auth failure)', () async {
      final bob = await crypto.deriveChatIdentity(
        masterSeed: bobSeed,
        host: 'h',
      );
      final alice = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final channelKey = crypto.generateChannelKey();

      final wrapped = await crypto.wrapKey(
        key: channelKey,
        recipientPublicKey: bob.publicKeyBytes,
      );

      // Alice's private key derives a different wrapping key → tag mismatch.
      await expectLater(
        crypto.unwrapKey(wrapped: wrapped, myKeyPair: alice.keyPair),
        throwsA(anything),
      );
    });

    test(
      'each wrap uses a fresh ephemeral key (ciphertext is non-deterministic)',
      () async {
        final bob = await crypto.deriveChatIdentity(
          masterSeed: bobSeed,
          host: 'h',
        );
        final channelKey = crypto.generateChannelKey();

        final w1 = await crypto.wrapKey(
          key: channelKey,
          recipientPublicKey: bob.publicKeyBytes,
        );
        final w2 = await crypto.wrapKey(
          key: channelKey,
          recipientPublicKey: bob.publicKeyBytes,
        );

        expect(w1.ephemeralPublicKey, isNot(w2.ephemeralPublicKey));
        expect(w1.ciphertext, isNot(w2.ciphertext));
        // …but both still unwrap to the same key.
        expect(
          await crypto.unwrapKey(wrapped: w1, myKeyPair: bob.keyPair),
          await crypto.unwrapKey(wrapped: w2, myKeyPair: bob.keyPair),
        );
      },
    );

    test('sealKeyringEntries seals the key to every member', () async {
      final alice = await crypto.deriveChatIdentity(
        masterSeed: aliceSeed,
        host: 'h',
      );
      final bob = await crypto.deriveChatIdentity(
        masterSeed: bobSeed,
        host: 'h',
      );
      final channelKey = crypto.generateChannelKey();

      final entries = await crypto.sealKeyringEntries(
        key: channelKey,
        members: [
          {'user_id': 'alice', 'chat_public_key': alice.publicKeyBase64},
          {'user_id': 'bob', 'chat_public_key': bob.publicKeyBase64},
        ],
      );

      expect(entries.map((e) => e['user_id']), ['alice', 'bob']);
      // Every member must recover the identical key — a keyring entry built
      // even slightly wrong locks that member out of the channel.
      for (final (index, identity) in [alice, bob].indexed) {
        expect(
          await crypto.unwrapKey(
            wrapped: WrappedKey.fromJson(entries[index]),
            myKeyPair: identity.keyPair,
          ),
          channelKey,
        );
      }
    });

    test('sealKeyringEntries on no members produces no entries', () async {
      expect(
        await crypto.sealKeyringEntries(
          key: crypto.generateChannelKey(),
          members: const [],
        ),
        isEmpty,
      );
    });
  });

  group('encryptBytes / decryptBytes (attachment blobs)', () {
    final data = Uint8List.fromList(List<int>.generate(5000, (i) => i & 0xff));

    test('round-trips arbitrary bytes', () async {
      final key = crypto.generateFileKey();
      final enc = await crypto.encryptBytes(data: data, key: key);
      final dec = await crypto.decryptBytes(
        ciphertext: enc.ciphertext,
        key: key,
        iv: enc.iv,
      );
      expect(dec, data);
    });

    test('a fresh file key is 32 bytes and random', () {
      final a = crypto.generateFileKey();
      final b = crypto.generateFileKey();
      expect(a.length, 32);
      expect(a, isNot(b));
    });

    test('the wrong key throws (AES-GCM auth failure)', () async {
      final key = crypto.generateFileKey();
      final wrong = crypto.generateFileKey();
      final enc = await crypto.encryptBytes(data: data, key: key);
      await expectLater(
        crypto.decryptBytes(ciphertext: enc.ciphertext, key: wrong, iv: enc.iv),
        throwsA(anything),
      );
    });

    test('tampered ciphertext throws', () async {
      final key = crypto.generateFileKey();
      final enc = await crypto.encryptBytes(data: data, key: key);
      final tampered = Uint8List.fromList(enc.ciphertext)
        ..[0] = enc.ciphertext[0] ^ 0xff;
      await expectLater(
        crypto.decryptBytes(ciphertext: tampered, key: key, iv: enc.iv),
        throwsA(anything),
      );
    });

    // Test case 15 of the GCM specification. The Rust cipher the app swaps in
    // checks itself against the same vector (rust/src/blob_cipher.rs), which
    // is what makes a blob from one open in the other.
    test('matches the GCM specification vector', () async {
      Uint8List hex(String s) => Uint8List.fromList([
        for (var i = 0; i < s.length; i += 2)
          int.parse(s.substring(i, i + 2), radix: 16),
      ]);
      final key = hex(
        'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
      );
      final nonce = hex('cafebabefacedbaddecaf888');
      final plain = hex(
        'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
        '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255',
      );
      final sealed = hex(
        '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad'
        'b094dac5d93471bdec1a502270e3cc6c',
      );
      const cipher = DartBlobCipher();
      expect(await cipher.seal(data: plain, key: key, nonce: nonce), sealed);
      expect(await cipher.open(sealed: sealed, key: key, nonce: nonce), plain);
    });
  });

  group('sealMessage / openMessage', () {
    // Ed25519 auth identity doubles as the message signing key.
    Future<({dynamic id, Uint8List pub})> senderIdentity() async {
      final id = await crypto.deriveServerIdentity(
        masterSeed: aliceSeed,
        host: 'h',
        serverId: 's1',
      );
      return (id: id, pub: id.publicKeyBytes);
    }

    test('round-trips plaintext for a valid signature + key', () async {
      final sender = await senderIdentity();
      final key = crypto.generateChannelKey();

      final env = await crypto.sealMessage(
        plaintext: 'hello world',
        messageKey: key,
        signingKeyPair: sender.id.keyPair,
        contextId: 'channel-1',
        keyVersion: 1,
      );
      final opened = await crypto.openMessage(
        envelope: env,
        messageKey: key,
        senderPublicKey: sender.pub,
        contextId: 'channel-1',
      );

      expect(opened, 'hello world');
    });

    test('a forged sender (wrong public key) is rejected → null', () async {
      final sender = await senderIdentity();
      final key = crypto.generateChannelKey();
      final imposter = await crypto.deriveServerIdentity(
        masterSeed: bobSeed,
        host: 'h',
        serverId: 's1',
      );

      final env = await crypto.sealMessage(
        plaintext: 'transfer approved',
        messageKey: key,
        signingKeyPair: sender.id.keyPair,
        contextId: 'channel-1',
        keyVersion: 1,
      );
      final opened = await crypto.openMessage(
        envelope: env,
        messageKey: key,
        senderPublicKey: imposter.publicKeyBytes,
        contextId: 'channel-1',
      );

      expect(opened, isNull);
    });

    test('replaying an envelope into another channel is rejected → null '
        '(contextId is bound into the signature)', () async {
      final sender = await senderIdentity();
      final key = crypto.generateChannelKey();

      final env = await crypto.sealMessage(
        plaintext: 'secret',
        messageKey: key,
        signingKeyPair: sender.id.keyPair,
        contextId: 'channel-1',
        keyVersion: 1,
      );
      final opened = await crypto.openMessage(
        envelope: env,
        messageKey: key,
        senderPublicKey: sender.pub,
        contextId: 'channel-2', // replayed elsewhere
      );

      expect(opened, isNull);
    });

    test('a tampered keyVersion is rejected → null', () async {
      final sender = await senderIdentity();
      final key = crypto.generateChannelKey();

      final env = await crypto.sealMessage(
        plaintext: 'secret',
        messageKey: key,
        signingKeyPair: sender.id.keyPair,
        contextId: 'channel-1',
        keyVersion: 1,
      );
      final tampered = MessageEnvelope(
        ciphertext: env.ciphertext,
        nonce: env.nonce,
        signature: env.signature,
        keyVersion: 2, // signature covered version 1
      );
      final opened = await crypto.openMessage(
        envelope: tampered,
        messageKey: key,
        senderPublicKey: sender.pub,
        contextId: 'channel-1',
      );

      expect(opened, isNull);
    });

    test(
      'a valid signature but wrong message key throws (AES-GCM auth failure)',
      () async {
        final sender = await senderIdentity();
        final key = crypto.generateChannelKey();
        final wrongKey = crypto.generateChannelKey();

        final env = await crypto.sealMessage(
          plaintext: 'secret',
          messageKey: key,
          signingKeyPair: sender.id.keyPair,
          contextId: 'channel-1',
          keyVersion: 1,
        );

        await expectLater(
          crypto.openMessage(
            envelope: env,
            messageKey: wrongKey,
            senderPublicKey: sender.pub,
            contextId: 'channel-1',
          ),
          throwsA(anything),
        );
      },
    );
  });

  group('reading a row that is not a sealed envelope', () {
    // Found by opening a channel that held one. A command written straight
    // against the schema leaves `nonce` and `signature` null — both are
    // nullable — and casting them to String threw. Because
    // the throw happened outside the decrypt loop's try, it took the whole
    // channel with it: no list, no error, a spinner forever.
    test('a null nonce and signature read as empty, not as a crash', () {
      final envelope = MessageEnvelope.fromJson({
        'ciphertext': '/play something',
        'nonce': null,
        'signature': null,
        'key_version': 0,
      });
      expect(envelope.nonce, isEmpty);
      expect(envelope.signature, isEmpty);
      expect(envelope.ciphertext, '/play something');
      expect(envelope.keyVersion, 0);
    });

    test('missing keys read the same way', () {
      final envelope = MessageEnvelope.fromJson({'key_version': 0});
      expect(envelope.nonce, isEmpty);
      expect(envelope.signature, isEmpty);
      expect(envelope.ciphertext, isEmpty);
    });

    test('a sealed row still reads exactly as before', () {
      final envelope = MessageEnvelope.fromJson({
        'ciphertext': 'c',
        'nonce': 'n',
        'signature': 's',
        'key_version': 3,
      });
      expect(envelope.nonce, 'n');
      expect(envelope.signature, 's');
      expect(envelope.keyVersion, 3);
    });

    test('an empty nonce is what the payload has always signed', () {
      // So a command signed with `signPlaintext` and one read back from a row
      // with a null nonce produce the same canonical string.
      expect(
        MessageEnvelope.signedPayload(
          contextId: 'chan',
          keyVersion: 0,
          nonce: '',
          ciphertext: '/play',
        ),
        'chatmsg:v1:chan:0::/play',
      );
    });
  });
}
