/// Machine-readable error codes returned in every API error response.
///
/// Keep in sync with `_shared/error_codes.ts` on the server side.
/// Both use identical snake_case string values so client code can switch on
/// [APIResponse.errorCode] instead of doing fragile substring matches on the
/// human-readable [APIResponse.error] message.
class ErrorCode {
  ErrorCode._();

  // ── Token / session ─────────────────────────────────────────────────────────
  /// Token field was absent in the request.
  static const String tokenMissing = 'token_missing';

  /// Token was not found in the database (e.g. manually deleted).
  static const String tokenInvalid = 'token_invalid';

  /// The session has aged out. Minted by the client rather than sent by an
  /// edge function: sessions are GoTrue's, so what actually arrives is a
  /// PostgREST "JWT expired", which `ServerDb` turns into this so the rest
  /// of the app has one thing to test.
  static const String tokenExpired = 'token_expired';

  // ── Auth flow ───────────────────────────────────────────────────────────────
  /// Ed25519 signature verification failed.
  static const String signatureInvalid = 'signature_invalid';

  // ── User ─────────────────────────────────────────────────────────────────────
  static const String userNotFound = 'user_not_found';
  static const String userBanned = 'user_banned';

  /// Asked to move a member who isn't in a voice channel — there is no
  /// connection to tell, so there is nothing to move.
  static const String userNotInVoice = 'user_not_in_voice';

  /// The call already holds `max_voice_participants` people.
  /// Not a permission failure and not a fault: a seat may free up at any
  /// moment, so the client offers to try again.
  static const String voiceChannelFull = 'voice_channel_full';

  // ── Server ───────────────────────────────────────────────────────────────────
  /// The server already holds `max_members` people. Returned
  /// by `register`, where it is the last refusal checked — everything above it
  /// is a fact about the caller, this is a fact about the server.
  static const String serverFull = 'server_full';
  static const String serverNotFound = 'server_not_found';
  static const String serverKeyInvalid = 'server_key_invalid';
  static const String serverCredentialsMissing = 'server_credentials_missing';

  // ── Channel ──────────────────────────────────────────────────────────────────
  static const String channelNotFound = 'channel_not_found';
  static const String channelNameDuplicate = 'channel_name_duplicate';
  static const String channelTypeInvalid = 'channel_type_invalid';
  static const String messageNotFound = 'message_not_found';

  // ── Chat ─────────────────────────────────────────────────────────────────────
  /// Another writer registered this key version first. Not a failure on its
  /// own: refetch the keyring, re-wrap against what is now current, post again.
  static const String keyringConflict = 'keyring_conflict';

  /// A message envelope was missing a field, or carried an oversized one.
  static const String envelopeInvalid = 'envelope_invalid';

  /// `chat_public_key` is not valid base64, or is not 32 bytes.
  static const String chatKeyInvalid = 'chat_key_invalid';

  /// A bot asked for a voice token before any member had sealed it a media
  /// key. Clears by itself once a member has been in the channel.
  static const String keyNotReady = 'key_not_ready';

  // ── DM calls ────────────────────────────────────────────────────────────────

  /// A call's room was asked for when the call is over, is not the caller's,
  /// or is not theirs to join yet — one code for all three.
  static const String callNotFound = 'call_not_found';

  // ── Registration ─────────────────────────────────────────────────────────────
  static const String inviteInvalid = 'invite_invalid';
  static const String inviteExhausted = 'invite_exhausted';
  static const String inviteExpired = 'invite_expired';
  static const String identityTaken = 'identity_taken';
  static const String usernameTaken = 'username_taken';

  /// Outside the alphabet `@`-mentions can express — see `ServerUsername`.
  /// The forms refuse it at the keystroke, so this is for a caller that went
  /// round them, such as a bot registering through the SDK.
  static const String usernameInvalid = 'username_invalid';

  /// public_key field is not valid base64 or not exactly 32 bytes.
  static const String invalidPublicKey = 'invalid_public_key';

  /// stable_id field is not valid base64 or not exactly 32 bytes.
  static const String invalidStableId = 'invalid_stable_id';

  // ── Permissions ───────────────────────────────────────────────────────────────
  static const String permissionDenied = 'permission_denied';

  // ── Operator limits ───────────────────────────────────────────────────────────
  /// A limit an admin tried to save is negative, or the attachment cap is
  /// outside what Storage will accept.
  static const String limitInvalid = 'limit_invalid';

  /// The sender is out of daily DMs. Raised by central's `send_dm` RPC; a
  /// self-hosted server has no message quota.
  static const String quotaExceeded = 'quota_exceeded';

  // ── Client-side ───────────────────────────────────────────────────────────────
  /// No socket: the connection was refused, or the host did not resolve.
  /// Minted by the client, not the server — when the server is down there is
  /// nobody to send a code.
  static const String serverUnreachable = 'server_unreachable';

  /// A socket opened but the call ran out of time. Kept apart from
  /// [serverUnreachable] because it means something different to the reader:
  /// the server is there, it is just too slow or too busy to answer.
  static const String serverTimeout = 'server_timeout';

  // ── Central account (GoTrue) ─────────────────────────────────────────────────
  // Not Rift's codes and not in `_shared/error_codes.ts`: these are Supabase's
  // own auth service speaking, passed through by
  // `SupabaseBackupRepository` so the cubit can act on them without matching
  // substrings of an English sentence that Supabase is free to reword.

  /// The account exists and the password was right, but the address has never
  /// been confirmed. The one error that is not a dead end: it means "finish
  /// signing up", and the answer to it is another confirmation email.
  static const String emailNotConfirmed = 'email_not_confirmed';

  /// Too many confirmation emails, too fast. Supabase enforces both a minimum
  /// gap between two emails to one address and an hourly cap for the whole
  /// project, and it is the second that bites — the built-in mail service is
  /// metered in single figures per hour.
  static const String emailSendRateLimited = 'over_email_send_rate_limit';

  // ── Generic ───────────────────────────────────────────────────────────────────
  static const String missingFields = 'missing_fields';
  static const String dbError = 'db_error';
  static const String unexpectedError = 'unexpected_error';

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Returns true for any code that means the session token is no longer
  /// valid and the client should attempt re-authentication.
  static bool isSessionInvalid(String? code) =>
      code == tokenInvalid || code == tokenExpired;

  /// Whether the same call, made again later, could plausibly succeed.
  ///
  /// True only for the two codes that describe the *connection* rather than
  /// the request: nothing answered, or nothing answered in time. Everything
  /// else is the server having considered the question and said no — a quota,
  /// a policy, an unfriending — and offering to try those again is a lie, both
  /// to the reader and about what the button does.
  ///
  /// This is what decides whether a failed send is kept as a retryable row or
  /// removed with an explanation. See `Outbox`.
  static bool isRetryable(String? code) =>
      code == serverUnreachable || code == serverTimeout;
}
