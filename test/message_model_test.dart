import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/user_permissions.dart';
import 'package:rift_crypto/rift_crypto.dart';

void main() {
  group('MessageEnvelope JSON', () {
    test('round-trips through toJson/fromJson with snake_case key_version', () {
      const env = MessageEnvelope(
        ciphertext: 'Y2lwaGVy',
        nonce: 'bm9uY2U=',
        signature: 'c2ln',
        keyVersion: 3,
      );
      final json = env.toJson();
      expect(json['key_version'], 3);

      final back = MessageEnvelope.fromJson(json);
      expect(back.ciphertext, env.ciphertext);
      expect(back.nonce, env.nonce);
      expect(back.signature, env.signature);
      expect(back.keyVersion, env.keyVersion);
    });
  });

  group('MessageEnvelope.signedPayload', () {
    test('binds every field — any change produces a different payload', () {
      String p({
        String contextId = 'c1',
        int keyVersion = 1,
        String nonce = 'n',
        String ciphertext = 'ct',
      }) => MessageEnvelope.signedPayload(
        contextId: contextId,
        keyVersion: keyVersion,
        nonce: nonce,
        ciphertext: ciphertext,
      );

      final base = p();
      expect(base, 'chatmsg:v1:c1:1:n:ct');
      expect(p(contextId: 'c2'), isNot(base)); // replay to another channel
      expect(p(keyVersion: 2), isNot(base)); // key-version confusion
      expect(p(nonce: 'n2'), isNot(base));
      expect(p(ciphertext: 'ct2'), isNot(base));
    });
  });

  group('WrappedKey JSON', () {
    test('round-trips through toJson/fromJson with snake_case keys', () {
      const wrapped = WrappedKey(
        ephemeralPublicKey: 'ZXBr',
        ciphertext: 'Y3Q=',
        nonce: 'bg==',
      );
      final json = wrapped.toJson();
      expect(
        json.keys,
        containsAll(['ephemeral_public_key', 'ciphertext', 'nonce']),
      );

      final back = WrappedKey.fromJson(json);
      expect(back.ephemeralPublicKey, wrapped.ephemeralPublicKey);
      expect(back.ciphertext, wrapped.ciphertext);
      expect(back.nonce, wrapped.nonce);
    });
  });

  group('UserPermissions', () {
    test('defaults to no privileges', () {
      const p = UserPermissions();
      expect(p.isServerAdmin, isFalse);
      expect(p.isChannelManager, isFalse);
      expect(p.canCreateTokens, isFalse);
    });

    test('fromJson tolerates missing keys (absent → false)', () {
      final p = UserPermissions.fromJson({'is_server_admin': true});
      expect(p.isServerAdmin, isTrue);
      expect(p.isChannelManager, isFalse);
      expect(p.canCreateTokens, isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      const p = UserPermissions(
        isServerAdmin: true,
        isChannelManager: false,
        canCreateTokens: true,
      );
      final back = UserPermissions.fromJson(p.toJson());
      expect(back.isServerAdmin, isTrue);
      expect(back.isChannelManager, isFalse);
      expect(back.canCreateTokens, isTrue);
    });

    test('copyWith overrides only the named field', () {
      const p = UserPermissions();
      final admin = p.copyWith(isServerAdmin: true);
      expect(admin.isServerAdmin, isTrue);
      expect(admin.isChannelManager, isFalse);
      // original is unchanged (immutability)
      expect(p.isServerAdmin, isFalse);
    });
  });
}
