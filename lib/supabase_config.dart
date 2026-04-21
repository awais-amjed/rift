/// Configuration class for Supabase connection details.
///
/// This class provides the necessary constants to connect to the Supabase
/// backend for the Mimba Mobile application. It contains the project URL
/// and the public anon key required for authentication and API access.
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
}
