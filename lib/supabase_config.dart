/// Configuration class for Supabase connection details.
///
/// This class provides the necessary constants to connect to the Supabase
/// backend for the central tier. It contains the project URL and the public
/// anon key required for authentication and API access.
class SupabaseConfig {
  /// The URL of the Supabase project instance.
  ///
  /// This URL is used to connect to the specific Supabase project
  /// for all API calls and realtime subscriptions.
  static const String supabaseUrl = 'https://fjkrobvftxqqapvhgtuw.supabase.co';

  /// The public anon key for Supabase authentication.
  ///
  /// This key is used for anonymous access to the Supabase backend.
  /// IMPORTANT: This is not a secret key and is safe to include in client-side code.
  /// It only grants access to public data and operations allowed for unauthenticated users.
  static const String supabaseKey =
      'sb_publishable_QIg5M_Ca1LfqDTWjzQIsEQ_Pwll01AC';

  /// Where a self-hosted server sends a push it cannot send itself.
  ///
  /// **A hostname we own, never a vendor URL.** This address is written into
  /// every self-hosted server's `push_config` at the moment its admin turns
  /// notifications on, so changing it is not a private decision — it costs
  /// every operator a re-enable. Behind this name the relay can move between
  /// Supabase, a Worker, Fly.io or a plain VPS as often as it likes, and no
  /// operator ever learns that it did.
  ///
  /// **It must resolve before push is enabled anywhere.** See
  /// `relay/README.md` for what has to exist behind it; the client checks it
  /// answers before writing it into a server, so a missing record is a
  /// sentence rather than a silence.
  static const String pushRelayEndpoint = 'https://push.joinrift.app';

  /// Where GoTrue sends someone after it has consumed a confirmation token.
  ///
  /// **Passed explicitly rather than left to the project's Site URL.** Site URL
  /// is the fallback for every email flow at once, so leaning on it would mean
  /// a future password reset landing on a page written to say "your email is
  /// confirmed". Naming the target per flow keeps each one able to answer the
  /// question it was actually asked.
  ///
  /// **It must also be in the project's redirect allow list.** GoTrue does not
  /// refuse an unlisted address — it quietly substitutes Site URL — so a typo
  /// here surfaces as people landing on the marketing page with no idea
  /// whether it worked.
  ///
  /// **The trailing slash is deliberate.** Pages serves this from a directory
  /// and answers the bare path with a redirect. Browsers do carry a fragment
  /// across one, but the fragment here is a live session token, and an auth
  /// flow is a poor place to lean on that being true everywhere.
  static const String emailConfirmationRedirect =
      'https://joinrift.app/email-confirmation/';
}
