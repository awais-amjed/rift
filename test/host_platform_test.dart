import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/host_platform.dart';

void main() {
  // Windows builds capture a share on the GPU by default, so the switch to
  // turn it off must be there.
  test(
    'the GPU capture switch is offered on Windows',
    () => expect(HostPlatform.capturesShareOnGpu, isTrue),
    skip: !Platform.isWindows,
  );
}
