import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/mention_name_cache.dart';

/// The cache behind a highlighted `@name`.
///
/// It exists because its two halves were once kept apart — a set of asked
/// names on the cubit, a map of answers in its state — and only one of them
/// was cleared when the channel changed. Everything here is about the pair
/// staying in step.
void main() {
  late MentionNameCache cache;

  setUp(() => cache = MentionNameCache());

  group('asking', () {
    test('a name is asked about once', () {
      expect(cache.unasked(['admin']), ['admin']);
      expect(cache.unasked(['admin']), isEmpty);
    });

    test('case is not a different question', () {
      cache.unasked(['Admin']);
      expect(cache.unasked(['admin', 'ADMIN']), isEmpty);
    });

    test('a name asked about is still asked about when nobody answers', () {
      // Otherwise every message mentioning a name belonging to nobody asks the
      // server about it again.
      cache.unasked(['ghost']);
      cache.remember(const {});
      expect(cache.unasked(['ghost']), isEmpty);
    });

    test('only the new names in a batch are asked', () {
      cache.unasked(['alice']);
      expect(cache.unasked(['alice', 'bob']), ['bob']);
    });
  });

  group('answers', () {
    test('what came back is what renders', () {
      cache.unasked(['admin']);
      cache.remember({'admin': 'Admin'});
      expect(cache.names, {'admin': 'Admin'});
    });

    test('names are keyed lower-case, however the server cased them', () {
      cache.remember({'Admin': 'Admin'});
      expect(cache.names['admin'], 'Admin');
    });

    test('the map handed out cannot be edited from outside', () {
      cache.remember({'admin': 'Admin'});
      expect(() => cache.names['bob'] = 'Bob', throwsUnsupportedError);
    });
  });

  group('a lookup that failed', () {
    test('lets its names be asked again', () {
      // The bug this guards: offline, or mid token-refresh, the request comes
      // back empty. Treating that as "nobody answers to this name" leaves the
      // mention unresolvable for as long as the channel stays open.
      final wanted = cache.unasked(['admin']);
      cache.forget(wanted);
      expect(cache.unasked(['admin']), ['admin']);
    });

    test('forgetting one name leaves the others asked', () {
      cache.unasked(['alice', 'bob']);
      cache.forget(['bob']);
      expect(cache.unasked(['alice', 'bob']), ['bob']);
    });
  });

  group('changing channel', () {
    test('clears the answers and the questions together', () {
      // The whole reason this class exists. Clearing the answers and keeping
      // the questions meant the cubit believed it had already asked about
      // names it no longer had answers for, and never asked again — so every
      // `@name` drew as plain text, but only for people who had not typed it
      // themselves, because the composer refills the answers as a side effect.
      cache.unasked(['admin']);
      cache.remember({'admin': 'Admin'});

      cache.reset();

      expect(cache.names, isEmpty, reason: 'answers should be dropped');
      expect(
        cache.unasked(['admin']),
        ['admin'],
        reason: 'and the name asked again, or it can never resolve',
      );
    });

    test('a name is resolvable again in the next channel', () {
      // Resolution is channel-scoped: somebody invisible in a private channel
      // may be perfectly visible in the next one.
      cache.unasked(['admin']);
      cache.forget(['admin']);
      cache.reset();

      expect(cache.unasked(['admin']), ['admin']);
      cache.remember({'admin': 'Admin'});
      expect(cache.names['admin'], 'Admin');
    });
  });
}
