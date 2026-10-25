import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/presentation/common/speaking_ring.dart';

/// In-memory stand-in so the hydrated theme cubit can be built in tests.
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

void main() {
  setUp(() => HydratedBloc.storage = _MemoryStorage());

  testWidgets('the ring rounds its corners by as much as it spreads', (
    tester,
  ) async {
    const radius = 6.0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => ThemeCubit(),
          child: const Center(
            child: SpeakingRing(
              isSpeaking: true,
              bloom: 0,
              borderRadius: BorderRadius.all(Radius.circular(radius)),
              child: SizedBox.square(dimension: 24),
            ),
          ),
        ),
      ),
    );

    // At rest the hard ring spreads 2px. Keeping the avatar's 6px corner on
    // the 28px ring made it squarer than the avatar inside: the picture
    // seemed to turn square whenever somebody spoke.
    expect(
      find.descendant(
        of: find.byType(SpeakingRing),
        matching: find.byType(CustomPaint),
      ),
      paints..rrect(
        rrect: RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -2, 28, 28),
          const Radius.circular(radius + 2),
        ),
      ),
    );
  });

  testWidgets('a gap leaves clear space between the child and the ring', (
    tester,
  ) async {
    const radius = 6.0;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider(
          create: (_) => ThemeCubit(),
          child: const Center(
            child: SpeakingRing(
              isSpeaking: true,
              bloom: 0,
              gap: 2,
              borderRadius: BorderRadius.all(Radius.circular(radius)),
              child: SizedBox.square(dimension: 24),
            ),
          ),
        ),
      ),
    );

    // A band from 2px out to 4px out, not a slab behind the avatar.
    expect(
      find.descendant(
        of: find.byType(SpeakingRing),
        matching: find.byType(CustomPaint),
      ),
      paints..drrect(
        outer: RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -4, 32, 32),
          const Radius.circular(radius + 4),
        ),
        inner: RRect.fromRectAndRadius(
          const Rect.fromLTWH(-2, -2, 28, 28),
          const Radius.circular(radius + 2),
        ),
      ),
    );
  });

  testWidgets('a ring holds still while its owner talks', (tester) async {
    Widget ring(bool speaking) => MaterialApp(
      home: BlocProvider(
        create: (_) => ThemeCubit(),
        child: Center(
          child: SpeakingRing(
            isSpeaking: speaking,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            child: const SizedBox.square(dimension: 24),
          ),
        ),
      ),
    );

    // A ring that breathed asked for a frame every vsync for as long as
    // anyone talked: the whole window redrawn sixty times a second, behind
    // a game too. It fades in and then asks for nothing.
    await tester.pumpWidget(ring(false));
    await tester.pumpWidget(ring(true));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(
      find.descendant(
        of: find.byType(SpeakingRing),
        matching: find.byType(CustomPaint),
      ),
      paints..rrect(),
    );

    // And fades out when they stop, leaving nothing drawn.
    await tester.pumpWidget(ring(false));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SpeakingRing),
        matching: find.byType(CustomPaint),
      ),
      isNot(paints..rrect()),
    );
  });
}
