import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../logic/services/app_log.dart';
import '../classes/api_response.dart';

/// Sending a bug report to Rift's team — central's `submit_bug_report`, then
/// the app's log files into the report's folder in the `bug-reports` bucket.
///
/// Like a listing report, this is the only part the app holds: reports are
/// read on the admin site, by moderator accounts.
class BugReportRepository {
  SupabaseClient get _client => Supabase.instance.client;

  static const _bucket = 'bug-reports';

  /// Files one report carries — central's `bug_report_file_limit()`. The
  /// newest: this session's, and the ones before it, since a crash is
  /// reported from the session after it.
  static const fileLimit = 4;

  /// Mirrors `bug_reports.description`.
  static const maxDescription = 4000;

  /// Send [description] with this copy's version and system and its newest
  /// log files. Answers success once the report is filed, even if a log
  /// failed to upload: the words are the report, and the logs help.
  Future<APIResponse> send(String description) async {
    final String reportId;
    try {
      final about = await AppLog.about();
      reportId =
          await _client.rpc(
                'submit_bug_report',
                params: {
                  'p_description': description,
                  'p_version': about.version,
                  'p_system': _clip(about.system, 300),
                },
              )
              as String;
    } on PostgrestException catch (e) {
      final identifier = e.message.trim();
      return APIResponse.error(
        _messages[identifier] ?? e.message,
        errorCode: identifier,
      );
    } catch (e) {
      return APIResponse.error(e);
    }

    final uid = _client.auth.currentUser?.id;
    if (uid == null) return APIResponse.success(null);
    var failed = 0;
    for (final file in await _logFiles()) {
      try {
        await _client.storage
            .from(_bucket)
            .uploadBinary(
              '$uid/$reportId/${file.name}',
              file.bytes,
              fileOptions: FileOptions(contentType: file.type),
            );
      } catch (e) {
        failed++;
        AppLog.write('BugReport: ${file.name} did not upload – $e');
      }
    }
    return APIResponse.success(failed);
  }

  /// The newest [fileLimit] logs, each gzipped off the UI thread. The web
  /// keeps its lines in memory and has no gzip, so it sends them as text.
  Future<List<({String name, Uint8List bytes, String type})>>
  _logFiles() async {
    if (kIsWeb) {
      final text = AppLog.memoryLines.join('\n');
      return [
        (
          name: 'web.log',
          bytes: Uint8List.fromList(utf8.encode(text)),
          type: 'text/plain',
        ),
      ];
    }
    final dir = AppLog.directory;
    if (dir == null || !await dir.exists()) return const [];
    final logs = <(DateTime, File)>[];
    await for (final entry in dir.list()) {
      final name = entry.uri.pathSegments.last;
      if (entry is File && name.startsWith('rift-') && name.endsWith('.log')) {
        logs.add((await entry.lastModified(), entry));
      }
    }
    logs.sort((a, b) => b.$1.compareTo(a.$1));
    final files = <({String name, Uint8List bytes, String type})>[];
    for (final (_, file) in logs.take(fileLimit)) {
      final path = file.path;
      try {
        final bytes = await Isolate.run(
          () => Uint8List.fromList(gzip.encode(File(path).readAsBytesSync())),
        );
        files.add((
          name: '${file.uri.pathSegments.last}.gz',
          bytes: bytes,
          type: 'application/gzip',
        ));
      } catch (e) {
        AppLog.write('BugReport: could not read $path – $e');
      }
    }
    return files;
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);

  // Central raises bare identifiers; these are the ones a person can act on.
  static const _messages = {
    'not_authenticated': 'Sign in to your Rift account to send a report.',
    'reporter_has_no_profile':
        'Claim a handle on your Rift account before sending a report.',
    'bug_report_limit_reached':
        'You have sent as many reports as one account may in a day. Try '
        'again tomorrow.',
  };
}
