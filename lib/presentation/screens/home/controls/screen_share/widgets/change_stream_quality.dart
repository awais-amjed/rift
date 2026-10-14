import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/screenshare/screenshare_cubit.dart';

/// Changes the running share, and remembers what took for the next one —
/// the share dialog opens on the choices it was last given, and a change made
/// mid-share is the more recent choice.
Future<void> changeStreamQuality(
  BuildContext context, {
  int? fps,
  int? resolution,
  bool? shareAudio,
}) async {
  final appCubit = context.read<AppCubit>();
  final now = await context.read<ScreenshareCubit>().changeQuality(
    fps: fps,
    resolution: resolution,
    shareAudio: shareAudio,
  );
  if (now == null) return;
  appCubit.setScreenShareSettings(
    appCubit.state.screenShareSettings.copyWith(
      fps: now.fps,
      resolution: now.resolution,
      shareAudio: now.shareAudio,
    ),
  );
}
