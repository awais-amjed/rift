/// Rift's cryptography, with the Flutter taken out.
///
/// This was inside the app package, and `bot_sdk` depended on the whole of
/// Rift to reach it — a headless bot pulling in a Flutter SDK to sign a string.
/// The alternative was a second implementation of the signing format, and two
/// implementations of a canonical payload are two things that can disagree:
/// a message signed over a payload differing by one character stores fine,
/// verifies as false, and renders as nothing.
///
/// So it lives here instead, and both sides depend on one copy. What is frozen
/// about the formats is in `WIRE.md` and `test/wire_vectors.json`; this is the
/// code those describe.
library;

export 'src/chat_identity.dart';
export 'src/crypto_repository.dart';
export 'src/message_envelope.dart';
export 'src/server_identity.dart';
export 'src/wrapped_key.dart';
