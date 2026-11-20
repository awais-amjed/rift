import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/classes/participant_info.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/services/voice_status_icons.dart';
import 'package:rift/presentation/screens/home/participants_grid/participants_tile/participant_name_badge.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/voice_status_row_icons.dart';

/// Someone keeping the call for clips is marked by their name, on their tile
/// and their row in the sidebar, so nobody has to remember the notice.
Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(extensions: [ThemeState()]),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('the tile badge says when they have clipping on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ParticipantNameBadge(
          name: 'Sam',
          isMicEnabled: true,
          isMuted: false,
          isClipping: true,
        ),
      ),
    );
    expect(find.byTooltip('Clipping on'), findsOneWidget);
  });

  testWidgets('and says nothing when they do not', (tester) async {
    await tester.pumpWidget(
      _host(
        const ParticipantNameBadge(
          name: 'Sam',
          isMicEnabled: true,
          isMuted: false,
        ),
      ),
    );
    expect(find.byTooltip('Clipping on'), findsNothing);
  });

  testWidgets('a shared screen tile carries no clipping mark', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const ParticipantNameBadge(
          name: 'Sam',
          isMicEnabled: true,
          isMuted: false,
          isScreenshare: true,
          isClipping: true,
        ),
      ),
    );
    expect(find.byTooltip('Clipping on'), findsNothing);
  });

  testWidgets('the sidebar row marks it too', (tester) async {
    await tester.pumpWidget(
      _host(
        const VoiceStatusRowIcons(
          participant: ParticipantInfo(
            identity: 'u1',
            userId: 'u1',
            name: 'Sam',
            isClipping: true,
          ),
          mutedForYou: false,
        ),
      ),
    );
    expect(find.byTooltip('Clipping on'), findsOneWidget);
  });

  test('clipping is listed after what they share, before the mic', () {
    const sam = ParticipantInfo(
      identity: 'u1',
      userId: 'u1',
      name: 'Sam',
      isClipping: true,
      isSharingScreen: true,
      isMicrophoneEnabled: false,
    );
    expect(voiceStatusIcons(sam, mutedForYou: false), [
      VoiceStatusIcon.sharingScreen,
      VoiceStatusIcon.clipping,
      VoiceStatusIcon.muted,
    ]);
  });

  test('nobody clipping, no mark', () {
    const sam = ParticipantInfo(identity: 'u1', userId: 'u1', name: 'Sam');
    expect(
      voiceStatusIcons(sam, mutedForYou: false),
      isNot(contains(VoiceStatusIcon.clipping)),
    );
  });
}
