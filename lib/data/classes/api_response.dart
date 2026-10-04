import '../../logic/helper_methods.dart';

/// What every server call hands back, success or not: the `{success, data, error,
/// code}` envelope the Edge Functions always answer with a 200. Read [success]
/// before [data]; an HTTP status never carries the outcome.
class APIResponse {
  final bool success;

  /// Human-readable error message (for display / logging).
  final String? error;

  /// Machine-readable error code from [ErrorCode] (for client logic).
  /// Always present on error responses from the server.
  final String? errorCode;

  final dynamic data;

  /// When the server answered, by its own clock: the HTTP `Date` header. What
  /// a sign-in is re-dated by when this device's clock is wrong. Null when
  /// there was no answer, and on the web unless the server exposes the header
  /// to other origins.
  final DateTime? serverTime;

  APIResponse({
    required this.success,
    this.data,
    this.error,
    this.errorCode,
    this.serverTime,
  });

  factory APIResponse.success(dynamic data) {
    return APIResponse(success: true, data: data);
  }

  factory APIResponse.error(dynamic error, {String? errorCode}) {
    return APIResponse(
      success: false,
      error: _errorToString(error),
      errorCode: errorCode,
    );
  }

  static String _errorToString(dynamic e) {
    // Log the error for debugging purposes
    HelperMethods.printDebug(e);

    // If the error is already a string, return it directly
    if (e is String) return e;

    try {
      // First try to get the details property (common in many error objects)
      return e.details;
    } catch (e2) {
      try {
        // Then try to get the message property (used in some API errors)
        return e.message;
      } catch (e) {
        // Fall back to a generic error message if all else fails
        return 'Unexpected error occurred. Please try again later.';
      }
    }
  }
}
