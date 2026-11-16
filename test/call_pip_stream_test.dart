import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/services/call_pip_stream.dart';

void main() {
  test('the stream last opened on the stage, not the one watched last', () {
    expect(callPipStream({'alice', 'bob'}, lookedAt: 'alice'), 'alice');
  });

  test('one no longer watched gives way to the one watched last', () {
    expect(callPipStream({'alice', 'bob'}, lookedAt: 'carol'), 'bob');
  });

  test('none opened yet: the one watched last', () {
    expect(callPipStream({'alice', 'bob'}, lookedAt: null), 'bob');
  });

  test('nothing watched: nothing floats', () {
    expect(callPipStream(const {}, lookedAt: 'alice'), isNull);
  });
}
