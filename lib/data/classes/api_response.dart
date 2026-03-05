import '../../logic/helper_methods.dart';

class APIResponse {
  final bool success;

  final String? error;

  final dynamic data;

  APIResponse({required this.success, this.data, this.error});

  factory APIResponse.success(dynamic data) {
    return APIResponse(success: true, data: data);
  }

  factory APIResponse.error(dynamic error) {
    return APIResponse(success: false, error: _errorToString(error));
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
