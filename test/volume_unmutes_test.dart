import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rift/data/participant_identity.dart';
import 'package:rift/logic/cubits/app/app_cubit.dart';
import 'package:rift/logic/cubits/livekit/livekit_cubit.dart';
import 'package:rift/logic/cubits/theme/theme_cubit.dart';
import 'package:rift/logic/cubits/vault/vault_cubit.dart';
import 'package:rift/presentation/common/volume_slider.dart';
import 'package:rift/presentation/screens/home/sidebar/widgets/participant_volume_slider.dart';

import 'support/memory_storage.dart';

/// Moving a volume while that sound is muted for you turns it back on at the
/// new level, as a player does. The slider used to go dead instead, so a
/// muted person could not be set louder or quieter until unmuted first.
void main() {
  setUp(() => HydratedBloc.storage = MemoryStorage());

  ({AppCubit app, LiveKitCubit livekit}) build() {
    final app = AppCubit();
    return (
      app: app,
      livekit: LiveKitCubit(appCubit: app, vaultCubit: VaultCubit()),
    );
  }

  test('a person\'s volume unmutes them', () async {
    final c = build();
    await c.livekit.setParticipantMute('u1', true);
    await c.livekit.setParticipantVolume('u1', 0.5);
    final setting = c.app.state.settingFor('u1');
    expect(setting.muted, isFalse);
    expect(setting.volume, 0.5);
  });

  test('a share\'s volume unmutes the share alone', () async {
    final c = build();
    const share = 'u1:screen';
    c.livekit.setMuteFor('u1', true);
    c.livekit.setMuteFor(share, true);
    await c.livekit.setVolumeFor(share, 0.3);
    expect(c.app.state.settingFor(share).muted, isFalse);
    expect(c.app.state.settingFor('u1').muted, isTrue);
  });

  test('a soundboard volume unmutes their soundboard', () {
    final app = AppCubit();
    app.setSoundboardMutedFor('u1', true);
    app.setSoundboardVolumeFor('u1', 0.4);
    final key = ParticipantIdentity.soundboardSettingsKey('u1');
    expect(app.state.settingFor(key).muted, isFalse);
    expect(app.state.settingFor(key).volume, 0.4);
  });

  testWidgets('the slider stays live while they are muted', (tester) async {
    final c = build();
    await c.livekit.setParticipantMute('u1', true);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ThemeCubit()),
          BlocProvider.value(value: c.app),
          BlocProvider.value(value: c.livekit),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: ParticipantVolumeSlider(
                target: 'u1',
                isMuted: true,
                volume: 1.0,
              ),
            ),
          ),
        ),
      ),
    );
    final slider = tester.widget<VolumeSlider>(find.byType(VolumeSlider));
    expect(slider.onChanged, isNotNull);

    await tester.tap(find.byType(Slider));
    await tester.pump();
    expect(c.app.state.settingFor('u1').muted, isFalse);
  });
}
