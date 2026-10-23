import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/data/repositories/update_repository.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/update/update_cubit.dart';
import 'package:rift/logic/services/linux_desktop_entry.dart';
import 'package:rift/presentation/screens/settings/widgets/about/updates_section.dart';
import 'package:rift/src/rust/api/updater.dart';

class _MemoryStorage implements Storage {
  final Map<String, dynamic> _data = {};

  @override
  dynamic read(String key) => _data[key];

  @override
  Future<void> write(String key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> clear() async => _data.clear();

  @override
  Future<void> close() async {}
}

/// The updater without Rust: [found] is what a check finds, and each
/// download is a stream the test feeds.
class _FakeUpdates implements UpdateRepository {
  AvailableUpdate? found = const AvailableUpdate(
    version: '1.5.0-beta.10',
    notesMarkdown: 'Notes',
    downloadBytes: 50 * 1024 * 1024,
  );
  final downloads = <StreamController<UpdateDownloadProgress>>[];
  final calls = <String>[];

  @override
  String? get installed => '1.5.0-beta.9';

  @override
  Future<AvailableUpdate?> check({required bool includePrereleases}) async =>
      found;

  @override
  Stream<UpdateDownloadProgress> download() {
    calls.add('download');
    final controller = StreamController<UpdateDownloadProgress>();
    downloads.add(controller);
    return controller.stream;
  }

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> cancel() async => calls.add('cancel');

  @override
  Future<void> applyOnExit() async {}
}

const _mb = 1024 * 1024;

UpdateDownloadProgress _at(int mb, {int total = 50, int perSecond = 0}) =>
    UpdateDownloadProgress(
      downloadedBytes: mb * _mb,
      totalBytes: total * _mb,
      bytesPerSecond: perSecond,
    );

void main() {
  group('the update download', () {
    late _FakeUpdates updates;
    late UpdateCubit cubit;

    setUp(() {
      HydratedBloc.storage = _MemoryStorage();
      updates = _FakeUpdates();
      cubit = UpdateCubit(appCubit: AppCubit(), repository: updates);
    });

    tearDown(() => cubit.close());

    test('waits for the person after a check they made', () async {
      await cubit.checkNow();
      expect(cubit.state.status, UpdateStatus.available);
      expect(cubit.state.version, '1.5.0-beta.10');
      expect(cubit.state.totalBytes, 50 * _mb);
      expect(updates.calls, isEmpty);
    });

    test('a check the person made puts the timer\'s next one off', () {
      fakeAsync((time) {
        final early = UpdateCubit(appCubit: AppCubit(), repository: updates);
        time.elapse(const Duration(seconds: 5));
        unawaited(early.checkNow());
        time.elapse(UpdateCubit.firstCheckAfter * 2);
        expect(early.state.status, UpdateStatus.available);
        expect(updates.calls, isEmpty);
        // Hours later the timer looks again, and downloads by itself.
        time.elapse(UpdateCubit.checkEvery);
        expect(early.state.status, UpdateStatus.downloading);
        expect(updates.calls, ['download']);
        unawaited(early.close());
      });
    });

    test('starts by itself after a check in the background', () async {
      await cubit.checkInBackground();
      expect(cubit.state.status, UpdateStatus.downloading);
      expect(updates.calls, ['download']);
    });

    test('shows how far and how fast, then is ready', () async {
      await cubit.checkNow();
      cubit.download();
      updates.downloads.single.add(_at(20, perSecond: 3 * _mb));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.downloadedBytes, 20 * _mb);
      expect(cubit.state.bytesPerSecond, 3 * _mb);
      expect(cubit.state.fraction, closeTo(0.4, 1e-9));
      await updates.downloads.single.close();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, UpdateStatus.ready);
    });

    test('pauses and resumes', () async {
      await cubit.checkNow();
      cubit.download();
      cubit.pause();
      expect(cubit.state.status, UpdateStatus.paused);
      // A report already on its way says nothing about speed while paused.
      updates.downloads.single.add(_at(20, perSecond: 3 * _mb));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, UpdateStatus.paused);
      expect(cubit.state.bytesPerSecond, 0);
      cubit.resume();
      expect(cubit.state.status, UpdateStatus.downloading);
      expect(updates.calls, ['download', 'pause', 'resume']);
    });

    test('a cancel leaves the update found, and the timer leaves it', () async {
      await cubit.checkInBackground();
      updates.downloads.single.add(_at(20));
      await Future<void>.delayed(Duration.zero);
      cubit.cancel();
      expect(cubit.state.status, UpdateStatus.available);
      expect(cubit.state.downloadedBytes, 0);
      expect(updates.calls, ['download', 'cancel']);
      // The stream's ending error after a cancel reaches nobody.
      updates.downloads.single.addError('cancelled');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, UpdateStatus.available);

      await cubit.checkInBackground();
      expect(cubit.state.status, UpdateStatus.available);
      expect(updates.downloads, hasLength(1));
      cubit.download();
      expect(cubit.state.status, UpdateStatus.downloading);
      expect(updates.downloads, hasLength(2));
    });

    test(
      'putting the package together cannot be paused or cancelled',
      () async {
        await cubit.checkNow();
        cubit.download();
        updates.downloads.single.add(_at(50));
        await Future<void>.delayed(Duration.zero);
        expect(cubit.state.preparing, isTrue);
        cubit.pause();
        cubit.cancel();
        expect(cubit.state.status, UpdateStatus.downloading);
        expect(updates.calls, ['download']);
      },
    );

    test('a failed download says so', () async {
      await cubit.checkNow();
      cubit.download();
      updates.downloads.single.addError('connection reset');
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.status, UpdateStatus.failed);
    });
  });

  group('the Updates line', () {
    const base = UpdateState(
      status: UpdateStatus.downloading,
      installedVersion: '1.5.0-beta.9',
      version: '1.5.0-beta.10',
      totalBytes: 50 * _mb,
      downloadedBytes: 20 * _mb,
      bytesPerSecond: 3 * _mb + _mb ~/ 5,
    );

    test('reads size, then progress and speed', () {
      expect(
        UpdatesSection.describe(base.copyWith(status: UpdateStatus.available)),
        '1.5.0-beta.10 is out (50 MB).',
      );
      expect(
        UpdatesSection.describe(base),
        'Downloading 1.5.0-beta.10: 20 MB of 50 MB · 3.2 MB/s',
      );
      expect(
        UpdatesSection.describe(base.copyWith(bytesPerSecond: 0)),
        'Downloading 1.5.0-beta.10: 20 MB of 50 MB',
      );
      expect(
        UpdatesSection.describe(base.copyWith(status: UpdateStatus.paused)),
        'Paused at 20 MB of 50 MB.',
      );
      expect(
        UpdatesSection.describe(base.copyWith(downloadedBytes: 50 * _mb)),
        'Getting 1.5.0-beta.10 ready…',
      );
    });
  });

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
