import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/tray_service/windows_tray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the runner's half of the channel, and notes what Dart asked.
  List<String> runnerAnswers(Object? Function(String method) answer) {
    final asked = <String>[];
    messenger.setMockMethodCallHandler(WindowsTray.channel, (call) async {
      asked.add(call.method);
      return answer(call.method);
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(WindowsTray.channel, null),
    );
    return asked;
  }

  /// A click in the runner, as it arrives from the main thread.
  Future<void> runnerSends(String method) async {
    await messenger.handlePlatformMessage(
      WindowsTray.channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  test('reports whether the runner made an icon', () async {
    runnerAnswers((_) => true);
    expect(await WindowsTray(onShow: () {}, onQuit: () {}).add(), isTrue);

    runnerAnswers((_) => false);
    expect(await WindowsTray(onShow: () {}, onQuit: () {}).add(), isFalse);
  });

  test(
    'a runner without the channel means no icon, not a failed start',
    () async {
      // No handler: the call ends in MissingPluginException, as it would on a
      // runner from before the tray moved.
      messenger.setMockMethodCallHandler(WindowsTray.channel, null);
      expect(await WindowsTray(onShow: () {}, onQuit: () {}).add(), isFalse);
    },
  );

  test('each menu choice reaches its own action, and only that', () async {
    runnerAnswers((_) => true);
    var shows = 0;
    var quits = 0;
    final tray = WindowsTray(onShow: () => shows++, onQuit: () => quits++);
    await tray.add();

    await runnerSends('show');
    expect((shows, quits), (1, 0));

    await runnerSends('quit');
    expect((shows, quits), (1, 1));
  });

  test('removing asks the runner to take the icon away', () async {
    final asked = runnerAnswers((_) => true);
    final tray = WindowsTray(onShow: () {}, onQuit: () {});
    await tray.add();
    await tray.remove();
    expect(asked, ['add', 'remove']);
  });

  // Dart's thread runs no message loop on Windows, so a window made there by
  // FFI never hears a click: beta.5 to beta.10 shipped an icon that did nothing.
  test('Windows does not make its tray through FFI on Dart\'s thread', () {
    final source = File(
      'lib/logic/services/tray_service/tray_service_native.dart',
    ).readAsStringSync();
    final branch = RegExp(
      r'if \(Platform\.isWindows\) \{(.*?)\} else \{',
      dotAll: true,
    ).firstMatch(source);
    expect(branch, isNotNull, reason: 'init chooses the tray by platform');
    expect(branch!.group(1), contains('WindowsTray('));
    expect(branch.group(1), isNot(contains('TrayIcon.create')));
  });
}
