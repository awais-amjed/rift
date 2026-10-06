import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/login_launch/login_launch.dart';

/// What the computer is told to run at sign-in. The runners look for the
/// minimized flag on their own, before any Dart runs, so it has to reach them
/// as a separate argument and not inside a quoted path.
void main() {
  group('Windows Run value', () {
    test('quotes the program and keeps the flags apart', () {
      expect(
        LoginLaunch.runCommand(
          r'C:\Users\a b\AppData\Local\Rift\current\rift.exe',
          ['--rift-profile=lana', LoginLaunch.minimizedFlag],
        ),
        r'"C:\Users\a b\AppData\Local\Rift\current\rift.exe" '
        '--rift-profile=lana --minimized',
      );
    });
  });

  group('Linux autostart entry', () {
    test('runs the program with its flags, and only while it exists', () {
      final entry = LoginLaunch.autostartEntry('/home/a b/Rift.AppImage', [
        LoginLaunch.minimizedFlag,
      ]);
      final lines = entry.split('\n');

      expect(lines, contains(r'Exec="/home/a b/Rift.AppImage" --minimized'));
      expect(lines, contains('TryExec=/home/a b/Rift.AppImage'));
      expect(lines, contains('X-GNOME-Autostart-enabled=true'));
    });

    test('a plain start passes nothing', () {
      final entry = LoginLaunch.autostartEntry('/opt/rift/rift', const []);

      expect(entry.split('\n'), contains('Exec=/opt/rift/rift'));
    });
  });

  test('reads the flag the runners act on', () {
    LoginLaunch.readArguments(['--rift-profile=lana', '--minimized']);
    expect(LoginLaunch.startedMinimized, isTrue);

    LoginLaunch.readArguments(const []);
    expect(LoginLaunch.startedMinimized, isFalse);
  });
}
