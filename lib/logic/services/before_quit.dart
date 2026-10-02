import 'dart:async';

/// Work that should finish before the app quits on purpose.
///
/// Quitting ends the process with every cubit still open — no `close()` runs —
/// so whatever a cubit does on its way out has to be asked for here instead.
/// The chat cubits use it to save the open conversation as *left*, which is
/// the one moment this device's own sends are fetched into its saved copy.
///
/// Each task gets [budget] at most, together: quitting is never held up by a
/// server that does not answer. A task that fails or runs over is given up on,
/// and what it would have saved is put right by the next open's fresh page.
class BeforeQuit {
  BeforeQuit._();
  static final BeforeQuit instance = BeforeQuit._();

  static const budget = Duration(seconds: 3);

  final List<Future<void> Function()> _tasks = [];

  void add(Future<void> Function() task) => _tasks.add(task);

  void remove(Future<void> Function() task) => _tasks.remove(task);

  /// Runs every task at once and returns when all are done or [limit] has
  /// passed, whichever is first. Never throws.
  Future<void> run({Duration limit = budget}) async {
    final running = [
      for (final task in List.of(_tasks)) Future.sync(task).catchError((_) {}),
    ];
    if (running.isEmpty) return;
    await Future.wait(running).timeout(limit, onTimeout: () => const []);
  }
}
