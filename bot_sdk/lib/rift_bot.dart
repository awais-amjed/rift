/// Write a Rift bot.
///
/// A bot is a user whose seed lives in a config file instead of on a phone:
/// same login, same policies, no separate API. What this package saves you is
/// the wire format — deriving the identity, signing the way the app signs, and
/// the two queries that find your commands.
///
/// See `README.md` for the shape of a bot and what it can and cannot do.
library;

export 'src/bot.dart';
export 'src/bot_session.dart';
