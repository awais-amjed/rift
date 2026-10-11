import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/message_markup.dart';
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

  test('an address in the argument is cut out, the rest kept as typed', () {
    expect(linkStretches('*x* https://example.com/watch?v=k_Rs. ok'), [
      (text: '*x* ', url: null),
      (
        text: 'https://example.com/watch?v=k_Rs',
        url: 'https://example.com/watch?v=k_Rs',
      ),
      (text: '. ok', url: null),
    ]);
    expect(linkStretches('a@b.com'), [(text: 'a@b.com', url: null)]);
  });

  testWidgets('a link in the argument opens on a tap', (tester) async {
    final opened = <String>[];
    final span = commandMessageSpan(
      '/play youtu.be/abc',
      base: base,
      theme: theme,
      onLink: (url) => TapGestureRecognizer()..onTap = () => opened.add(url),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text.rich(span))));
    await tester.tap(find.byType(CommandArgument));
    expect(opened, ['https://youtu.be/abc']);
  });
}
