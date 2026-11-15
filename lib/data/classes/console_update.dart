import 'package:equatable/equatable.dart';

/// A newer release of a server's console, as the server tells its admins
/// (`console_update` in `get_server_details`, rift-self-host 029).
///
/// The console asks GitHub on its own and keeps the answer; the app only
/// says so. Updating stays in the console, so this carries what an admin
/// needs to go and do it: which version, its notes and where it was
/// published.
class ConsoleUpdate extends Equatable {
  final String version;

  /// The release's page. Shown and opened as given: it comes from the
  /// server, written there by its own console, and is only ever a link.
  final String url;

  final String notes;

  const ConsoleUpdate({
    required this.version,
    required this.url,
    required this.notes,
  });

  /// Null for anything but the shape the console writes: an odd value is
  /// nothing to tell, not a crash in the server's details.
  static ConsoleUpdate? tryParse(Object? json) {
    if (json is! Map) return null;
    final version = json['version'];
    if (version is! String || version.isEmpty) return null;
    final url = json['url'];
    final notes = json['notes'];
    return ConsoleUpdate(
      version: version,
      url: url is String ? url : '',
      notes: notes is String ? notes : '',
    );
  }

  @override
  List<Object?> get props => [version, url, notes];
}
