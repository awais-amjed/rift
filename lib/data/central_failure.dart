import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' hide ErrorCode;

import '../logic/helper_methods.dart';
import 'classes/api_response.dart';
import 'enums/error_code.dart';

/// Central not answering, put in words for somebody who has never heard of
/// it — what a self-hosted server's calls already do in `ServerRepository`.
///
/// Each Supabase client reports a dead central its own way, none of them
/// readable: the auth client wraps the socket error in a sentence
/// ("ClientException with SocketException: Connection refused"), PostgREST
/// and Storage carry the gateway's empty 502 as their message, and a plain
/// query throws the socket error itself. Shown as they came, a new user's
/// first sign-in failed with a stack of class names.
abstract final class CentralFailure {
  static const message =
      "Can't reach Rift's account server. It may be down for a moment, so "
      "try again in a few minutes. If other sites don't load either, check "
      'your internet connection.';

  /// The gateway in front of central answering for a service behind it that
  /// is down or restarting. A 500 is left out: GoTrue answers one for its own
  /// failures, such as a confirmation email it could not send, and its
  /// message says so.
  static const _gateway = {'502', '503', '504'};

  /// Whether [error] means central did not answer, rather than answered no.
  static bool isUnreachable(Object error) => switch (error) {
    AuthRetryableFetchException(:final statusCode) =>
      statusCode == null || _gateway.contains(statusCode),
    PostgrestException(:final code) => _gateway.contains(code),
    // A failed request leaves the error's type name where the status goes.
    StorageException(:final statusCode) =>
      statusCode != null &&
          (_gateway.contains(statusCode) || int.tryParse(statusCode) == null),
    FunctionException(:final status) => _gateway.contains('$status'),
    SocketException() || TimeoutException() || http.ClientException() => true,
    _ => false,
  };

  /// [error] as an [APIResponse]: the sentence above when central did not
  /// answer, otherwise whatever [APIResponse.error] makes of it.
  static APIResponse response(Object error) {
    if (!isUnreachable(error)) return APIResponse.error(error);
    // The raw error still goes in the log, where a bug report wants it.
    HelperMethods.printDebug('[Central] no answer: $error');
    return APIResponse.error(
      message,
      errorCode: error is TimeoutException
          ? ErrorCode.serverTimeout
          : ErrorCode.serverUnreachable,
    );
  }
}
