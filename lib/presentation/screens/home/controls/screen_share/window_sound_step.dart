import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../data/classes/screen_share_settings.dart';
import '../../../../../data/classes/share_sound_choice.dart';
import '../../../../../data/classes/shared_window.dart';
import '../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../logic/cubits/screenshare/share_attempt.dart';
import '../../../../../logic/helper_methods.dart';
import '../../../../../logic/services/host_platform.dart';
import '../../../../../logic/services/share_sound_match.dart';
import '../../../../../logic/services/window_share_portal.dart';
import '../../../../../src/rust/api/screenshare/types.dart';
import '../../../../common/show_custom_dialog.dart';
import '../../screenshare/share_sound/share_sound_dialog.dart';

/// A window share to start, once its window and sound are known: the
/// settings, and on GNOME and KDE the desktop's pick to share
/// (`ScreenShareConfig.portalChoice`).
typedef WindowShare = ({ScreenShareSettings settings, String? portalChoice});

/// Linux: what starting a window share with sound asks after the share
/// dialog. First the window — on GNOME and KDE the desktop's own picker, run
/// here rather than by the capture, so Rift learns whose window it is — then
/// the sound popup, starting on the sound remembered for the window's app, or
/// else a guess.
class WindowSoundStep {
  const WindowSoundStep._();

  static bool appliesTo(ScreenShareSettings settings) =>
      HostPlatform.matchesWindowSound &&
      !settings.captureFullScreen &&
      settings.shareAudio;

  /// The share to start, or null when the user backed out of the picker or
  /// the popup, or pressed Share again while waiting: [attempt] is given up
  /// then, and its picker with it. A later press may have started a share by
  /// the time this hears, so nothing more of this one is asked.
  static Future<WindowShare?> run(
    BuildContext context,
    ScreenShareSettings settings,
    ShareAttempt attempt,
  ) async {
    final app = context.read<AppCubit>();
    String? token;
    SharedWindow? window;
    if (HostPlatform.picksShareWindowItself) {
      final picked = await WindowSharePortal.pick(
        abandoned: attempt.whenAbandoned,
      );
      if (attempt.abandoned) {
        if (picked is WindowPicked) {
          unawaited(WindowSharePortal.forget(picked.token));
        }
        return null;
      }
      switch (picked) {
        case WindowPickCancelled():
          return null;
        // The capture asks for the window itself, as before.
        case WindowPickFailed():
          break;
        case WindowPicked(token: final chosen, window: final saved):
          token = chosen;
          window = saved;
      }
    } else {
      window = SharedWindow(
        appId: settings.selectedVideoSourceAppId ?? '',
        title: settings.selectedVideoSourceTitle ?? '',
        pid: settings.selectedVideoSourcePid,
      );
    }

    final key = window == null ? null : ShareSoundMatch.appKey(window);
    final saved = key == null ? null : settings.soundForApps[key];
    HelperMethods.printDebug(
      '$_tag: ${_describe(key)}, '
      '${saved == null ? 'no sound kept for it' : 'a sound kept for it'}',
    );

    final answer = context.mounted
        ? await showCustomDialog<ShareSoundAnswer>(
            context: context,
            build: (_) => ShareSoundDialog(window: window, saved: saved),
          )
        : null;
    if (answer == null) {
      if (token != null) unawaited(WindowSharePortal.forget(token));
      return null;
    }
    var chosen = _withSound(settings, answer.source);
    if (answer.remember && key != null) {
      final sounds = {
        ...app.state.screenShareSettings.soundForApps,
        key: ShareSoundChoice.of(answer.source),
      };
      app.setScreenShareSettings(
        app.state.screenShareSettings.copyWith(soundForApps: sounds),
      );
      chosen = chosen.copyWith(soundForApps: sounds);
      HelperMethods.printDebug(
        '$_tag: kept ${answer.source?.appName ?? 'every app'} for it',
      );
    }
    return (settings: chosen, portalChoice: token);
  }

  static const _tag = 'WindowSoundStep';

  /// The window as the log may name it: by its app, never by its title,
  /// which can say what is open in it.
  static String _describe(String? key) => key == null
      ? 'a window of no known app or title'
      : ShareSoundMatch.byTitle(key)
      ? 'a window known by its title'
      : 'a window of $key';

  static ScreenShareSettings _withSound(
    ScreenShareSettings settings,
    AudioSource? source,
  ) => source == null
      ? settings.copyWith(clearAudioSource: true)
      : settings.copyWith(selectedAudioSource: source);
}
