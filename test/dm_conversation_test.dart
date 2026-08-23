import 'package:flutter_test/flutter_test.dart';
import 'package:rift/data/classes/dm_conversation.dart';

/// Pins the central directory's column names to the mapping that reads them.
///
/// The August database rewrite renamed central's `user_id` to `id`. The
/// repository's query was updated and this mapping was not, so every handle
/// search threw `type 'Null' is not a subtype of type 'String'` and the search
/// drop-down hung on "Searching…" — with no error surfaced, because the throw
/// happened inside the debounced future the field awaits. Found Aug 23 2026
/// driving two real clients.
void main() {
  group('DmConversation.fromDirectoryRow', () {
    /// A row exactly as central's `users` table returns it.
    Map<String, dynamic> row({
      String id = 'e6b1f0c2-0000-4000-8000-000000000001',
      String handle = 'foxtrot_test',
      String? chatKey = 'Y2hhdA==',
      String? signingKey = 'c2lnbg==',
    }) => {
      'id': id,
      'handle': handle,
      'chat_public_key': chatKey,
      'signing_public_key': signingKey,
      'created_at': '2026-08-23T09:00:00Z',
    };

    test('reads id, not the pre-rewrite user_id', () {
      final convo = DmConversation.fromDirectoryRow(row());
      expect(convo.peerId, 'e6b1f0c2-0000-4000-8000-000000000001');
      expect(convo.peerName, 'foxtrot_test');
    });

    test('carries both published keys', () {
      final convo = DmConversation.fromDirectoryRow(row());
      expect(convo.peerChatPublicKey, 'Y2hhdA==');
      expect(convo.peerSigningPublicKey, 'c2lnbg==');
    });

    test('a peer who has published no keys maps to nulls, not a throw', () {
      // Someone who claimed a handle and has not opened the app since. They
      // are still findable — the row just can't be messaged yet.
      final convo = DmConversation.fromDirectoryRow(
        row(chatKey: null, signingKey: null),
      );
      expect(convo.peerChatPublicKey, isNull);
      expect(convo.peerSigningPublicKey, isNull);
      expect(convo.peerId, isNotEmpty);
    });

    test('a row missing id throws rather than silently mis-keying', () {
      final bad = row()..remove('id');
      expect(() => DmConversation.fromDirectoryRow(bad), throwsA(anything));
    });

    test('lastMessage is absent on a directory hit', () {
      // A search result is someone you may not have messaged at all.
      expect(DmConversation.fromDirectoryRow(row()).lastMessage, isNull);
    });
  });
}
