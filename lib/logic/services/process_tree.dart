import 'dart:io';

/// Linux: which process started which, from `/proc`.
class ProcessTree {
  const ProcessTree._();

  /// [pid]'s parent, or null when it is gone or cannot be read.
  static int? parentOf(int pid) {
    try {
      final stat = File('/proc/$pid/stat').readAsStringSync();
      // `pid (name) state ppid …`, and the name may hold spaces and
      // brackets of its own: the fields resume after the last one.
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      return int.tryParse(fields[1]);
    } catch (_) {
      return null;
    }
  }
}
