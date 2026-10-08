import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every model and every cubit state compares by value, and compares every
/// field.
///
/// `emit` drops a state equal to the current one, and `buildWhen`,
/// `listenWhen` and `BlocSelector` decide with `==` (`BEST_PRACTICES.md` §4).
/// A class with no equality rebuilds everything on every copy; a class whose
/// equality forgot a field is worse — a change to that field compares equal,
/// the emit is dropped, and the screen silently keeps the old value. Read
/// from the source, so a field added tomorrow fails here until it is listed.
void main() {
  /// Classes that are not state and are never compared, and why.
  const exempt = {
    // A call's outcome, read once by whoever made the call.
    'APIResponse',
  };

  final files = [
    ...Directory('lib/data/classes').listSync().whereType<File>(),
    ...Directory('lib/logic/cubits')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('_state.dart')),
  ].where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final unit = parseString(
      content: file.readAsStringSync(),
      throwIfDiagnostics: false,
    ).unit;
    for (final type in unit.declarations.whereType<ClassDeclaration>()) {
      final name = type.namePart.typeName.lexeme;
      if (exempt.contains(name) || type.abstractKeyword != null) continue;
      final fields = [
        for (final member in type.body.members.whereType<FieldDeclaration>())
          if (!member.isStatic)
            for (final variable in member.fields.variables)
              variable.name.lexeme,
      ];
      if (fields.isEmpty) continue;

      test('$name compares every field', () {
        final methods = {
          for (final m in type.body.members.whereType<MethodDeclaration>())
            m.name.lexeme: m.body.toSource(),
        };
        final equality = [?methods['=='], ?methods['props']];
        expect(
          equality,
          isNotEmpty,
          reason: '$name (${file.path}) has no == and no Equatable props',
        );
        // A helper the equality calls (`sameApartFromSpeaking`) counts as
        // part of it.
        final reached = [
          ...equality,
          for (final entry in methods.entries)
            if (equality.any((body) => body.contains('${entry.key}(')))
              entry.value,
        ].join('\n');
        final missing = [
          for (final field in fields)
            if (!RegExp('\\b$field\\b').hasMatch(reached)) field,
        ];
        expect(
          missing,
          isEmpty,
          reason: '$name (${file.path}) leaves these out of its equality',
        );
      });
    }
  }
}
