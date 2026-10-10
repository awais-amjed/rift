import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/chat/message_row/command_message_span.dart';

/// A command reads as an instruction to a program: its verb, then exactly
/// what the bot was handed, in the code face and never as markup.
void main() {
  final theme = ThemeState();
  const base = TextStyle(fontSize: 14);

  String? verbOf(TextSpan span) => (span.children!.first as TextSpan).text;
  String? argumentOf(TextSpan span) {
    final boxed = span.children!.whereType<WidgetSpan>();
    return boxed.isEmpty ? null : (boxed.single.child as CommandArgument).text;
  }

  test('the verb, then the argument boxed', () {
    final span = commandMessageSpan(
      '/play thats so true',
      base: base,
      theme: theme,
    );
    expect(verbOf(span), '/play');
    expect(argumentOf(span), 'thats so true');
  });

  test('markup is left as the characters the bot got', () {
    final span = commandMessageSpan(
      '/play *nsync_bye bye',
      base: base,
      theme: theme,
    );
    expect(argumentOf(span), '*nsync_bye bye');
  });

  test('a bare verb has no box', () {
    final span = commandMessageSpan('/stop', base: base, theme: theme);
    expect(verbOf(span), '/stop');
    expect(argumentOf(span), isNull);
  });

  test('spaces around the argument are not part of it', () {
    final span = commandMessageSpan('  /play   x  ', base: base, theme: theme);
    expect(verbOf(span), '/play');
    expect(argumentOf(span), 'x');
  });
}
