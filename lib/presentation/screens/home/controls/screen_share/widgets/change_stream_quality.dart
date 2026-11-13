import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';
import '../../../../../../src/rust/api/screenshare/types.dart';

/// Changes the running share, and remembers what took for the next one —
/// the share dialog opens on the choices it was last given, and a change made
/// mid-share is the more recent choice. A codec picked here is picked by
/// hand, so the dialog's Auto gives way to it.
Future<void> changeStreamQuality(
  BuildContext context, {
  int? fps,
  int? resolution,
  VideoCodec? codec,
  bool? shareAudio,
}) async {
  final appCubit = context.read<AppCubit>();
  final now = await context.read<ScreenshareCubit>().changeQuality(
    fps: fps,
    resolution: resolution,
    codec: codec,
    shareAudio: shareAudio,
  );
  if (now == null) return;
  appCubit.setScreenShareSettings(
    appCubit.state.screenShareSettings.copyWith(
      fps: now.fps,
      resolution: now.resolution,
      shareAudio: now.shareAudio,
      codec: codec == null ? null : now.codec,
      codecChosen: codec == null ? null : true,
    ),
  );
}
