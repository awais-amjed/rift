import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/services/linux_desktop_entry.dart';

void main() {
  group('beta updates', () {
    test('follow the installed version until chosen', () {
      const state = AppState();
      expect(state.wantsBetaUpdates('1.4.0-beta.1'), isTrue);
      expect(state.wantsBetaUpdates('1.4.0'), isFalse);
      expect(state.wantsBetaUpdates(null), isFalse);
    });

    test('a choice holds whatever is installed', () {
      expect(
        const AppState()
            .copyWith(betaUpdates: false)
            .wantsBetaUpdates('1.4.0-beta.1'),
        isFalse,
      );
      expect(
        const AppState().copyWith(betaUpdates: true).wantsBetaUpdates('1.4.0'),
        isTrue,
      );
    });

    test('the choice is saved', () {
      final json = const AppState().copyWith(betaUpdates: true).toJson();
      expect(AppState.fromJson(json).betaUpdates, isTrue);
      expect(AppState.fromJson(const AppState().toJson()).betaUpdates, isNull);
    });
  });

  group('Linux desktop entry', () {
    test('recognises its own entry, for any program', () {
      expect(
        LinuxDesktopEntry.isOwnEntry(
          LinuxDesktopEntry.entry('/home/a/Rift.AppImage', withIcon: true),
        ),
        isTrue,
      );
      expect(
        LinuxDesktopEntry.isOwnEntry(
          LinuxDesktopEntry.entry('/opt/rift-1.3.0-linux-x64/rift'),
        ),
        isTrue,
      );
    });

    test('recognises the four-line entry it wrote before', () {
      expect(
        LinuxDesktopEntry.isOwnEntry(
          '[Desktop Entry]\nType=Application\nName=Rift\n'
          'Exec=/opt/rift/rift\n',
        ),
        isTrue,
      );
    });

    test('leaves an entry someone else wrote alone', () {
      expect(
        LinuxDesktopEntry.isOwnEntry(
          '[Desktop Entry]\nType=Application\nName=Rift\nExec=rift %u\n'
          'MimeType=x-scheme-handler/rift;\n',
        ),
        isFalse,
      );
    });

    test('names its icon only when it has one', () {
      expect(
        LinuxDesktopEntry.entry('/a/Rift.AppImage', withIcon: true),
        contains('\nIcon=com.codingfries.rift\n'),
      );
      expect(
        LinuxDesktopEntry.entry('/a/Rift.AppImage'),
        isNot(contains('Icon=')),
      );
    });

    test('quotes a path with spaces, and reads it back', () {
      const path = r'/home/a/My Apps/Rift "beta" $1.AppImage';
      final entry = LinuxDesktopEntry.entry(path);
      expect(
        entry,
        contains(r'Exec="/home/a/My Apps/Rift \"beta\" \$1.AppImage"'),
      );
      expect(LinuxDesktopEntry.execOf(entry), path);
      expect(
        LinuxDesktopEntry.execOf(LinuxDesktopEntry.entry('/opt/rift/rift')),
        '/opt/rift/rift',
      );
    });
  });
}
