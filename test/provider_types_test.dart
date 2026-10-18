import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `BlocProvider.value` takes its type from the cubit handed to it — unless
/// it sits in a list typed `List<BlocProvider>`, where Dart infers it from the
/// list instead. Every provider in such a list is then registered as the base
/// type, `context.read<SoundboardCubit>()` below it finds none of them, and
/// the lookup quietly carries on upward to whatever is provided above: the
/// soundboard picker, opened mid-call on another server, showed that server's
/// empty library rather than the call's.
void main() {
  test('every BlocProvider in a typed list names its cubit', () {
    final listOfProviders = RegExp(r'List<BlocProvider>');
    final untyped = RegExp(r'^\s*BlocProvider\.value\(', multiLine: true);
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final code = entity.readAsStringSync();
      for (final match in listOfProviders.allMatches(code)) {
        // The list's literal, from its type to the closing `];`.
        final end = code.indexOf('];', match.end);
        final literal = code.substring(match.end, end < 0 ? code.length : end);
        if (untyped.hasMatch(literal)) offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
