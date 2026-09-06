/// Rift's cryptography, with the Flutter taken out.
///
/// This was inside the app package, which meant anything headless that needed
/// to sign a string had to pull in a Flutter SDK to get at it. It came out for
/// the Dart bot SDK, which has since been deleted (BOTS.md §11) — and it stays
/// out for a better reason than the one it left for.
///
/// **This is the reference implementation.** `tool/gen_wire_vectors.dart`
/// generates `test/wire_vectors.json` from this code, `test/wire_test.dart`
/// holds it to them, and the `rift-bot-sdk` repo proves itself against the same file
/// without reading a line of this one. Two implementations of a canonical
/// payload are two things that can disagree, and the disagreement does not look
/// like an error: a message signed over a payload differing by one character
/// stores fine, verifies as false, and renders as nothing. Meeting at a JSON
/// file is the only arrangement in which "they agree" means anything.
///
/// What is frozen about the formats is in `WIRE.md`; this is the code it
/// describes.
library;

export 'src/chat_identity.dart';
export 'src/crypto_repository.dart';
export 'src/message_envelope.dart';
export 'src/server_identity.dart';
export 'src/wrapped_key.dart';
