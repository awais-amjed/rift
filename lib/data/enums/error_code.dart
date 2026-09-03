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

  /// Token exists but its TTL has passed.
  static const String tokenExpired = 'token_expired';

  /// Token row has no associated user_id.
  static const String tokenUnlinked = 'token_unlinked';

  /// User exists but has no token row (unusual server-side state).
  static const String noSession = 'no_session';

  // ── Challenge / auth flow ────────────────────────────────────────────────────
  /// Nonce not found or already consumed.
  static const String challengeInvalid = 'challenge_invalid';

  /// Nonce TTL has passed before verify was called.
  static const String challengeExpired = 'challenge_expired';

  /// Ed25519 signature verification failed.
  static const String signatureInvalid = 'signature_invalid';

  // ── User ─────────────────────────────────────────────────────────────────────
  static const String userNotFound = 'user_not_found';
  static const String userBanned = 'user_banned';

  /// Asked to move a member who isn't in a voice channel — there is no
  /// connection to tell, so there is nothing to move.
  static const String userNotInVoice = 'user_not_in_voice';

  // ── Server ───────────────────────────────────────────────────────────────────
  static const String serverNotFound = 'server_not_found';
  static const String serverKeyInvalid = 'server_key_invalid';
  static const String serverCredentialsMissing = 'server_credentials_missing';

  // ── Channel ──────────────────────────────────────────────────────────────────
  static const String channelNotFound = 'channel_not_found';
  static const String channelNameDuplicate = 'channel_name_duplicate';
  static const String channelTypeInvalid = 'channel_type_invalid';
  static const String channelWrongServer = 'channel_wrong_server';

  // ── Key rotation ─────────────────────────────────────────────────────────────
  static const String keySame = 'key_same';
  static const String keyInUse = 'key_in_use';

  // ── Registration ─────────────────────────────────────────────────────────────
  static const String inviteInvalid = 'invite_invalid';
  static const String inviteExhausted = 'invite_exhausted';
  static const String inviteExpired = 'invite_expired';
  static const String identityTaken = 'identity_taken';
  static const String usernameTaken = 'username_taken';

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

  /// The sender is out of daily messages for this channel or for DMs. Raised by
  /// the quota trigger in migration 007, and by central's `send_dm` RPC — one
  /// code for the same wall on either tier.
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

  // ── Generic ───────────────────────────────────────────────────────────────────
  static const String missingFields = 'missing_fields';
  static const String dbError = 'db_error';
  static const String unexpectedError = 'unexpected_error';

  // ── Helpers ───────────────────────────────────────────────────────────────────

  /// Returns true for any code that means the session token is no longer
  /// valid and the client should attempt re-authentication.
  static bool isSessionInvalid(String? code) =>
      code == tokenInvalid || code == tokenExpired || code == tokenUnlinked;

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
