import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/audio_device_list/audio_device_list_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/services/audio_devices.dart';
import '../../../common/message_banner.dart';
import 'audio_device_picker.dart';

/// Over the widget budget and one job: picking the input and output devices,
/// which load and change together.
///
/// Section for selecting audio input and output devices.
class AudioDeviceSection extends StatefulWidget {
  const AudioDeviceSection({super.key});

  @override
  State<AudioDeviceSection> createState() => _AudioDeviceSectionState();
}

class _AudioDeviceSectionState extends State<AudioDeviceSection> {
  late final AudioDeviceListCubit _lists = context.read<AudioDeviceListCubit>();

  /// The read started last. A pick waits for it: the lists drawn meanwhile
  /// are the last ones read, perhaps before a call was joined or left, and
  /// whether a pick can be applied now ([AudioDeviceLists.live]) must be
  /// the current answer.
  late Future<void> _fresh;

  String? _selectionError;

  StreamSubscription<void>? _deviceChangeSub;

  @override
  void initState() {
    super.initState();
    _fresh = _lists.load();
    // Devices used to be read once and never again, so plugging a headset in
    // while this was open left a list that no longer described the machine.
    _deviceChangeSub = AudioDevices.changes.listen((_) => _reload());
  }

  @override
  void dispose() {
    _deviceChangeSub?.cancel();
    super.dispose();
  }

  void _reload() => _fresh = _lists.load();

  /// Applies a picked device, then records it.
  ///
  /// That order matters: recording the choice first meant a device the
  /// platform went on to refuse stayed saved and came back next launch.
  ///
  /// "System default" (a null [deviceId]) is applied too
  /// ([AudioDevices.systemDefault]): WebRTC keeps the last device it was given
  /// for the life of the process, so merely forgetting the choice left the
  /// call where it was.
  Future<void> _select(String? deviceId, {required bool isInput}) async {
    await _fresh;
    if (!mounted) return;
    final lists = _lists.state;
    if (!lists.live) return _save(deviceId, isInput: isInput);
    final device = deviceId == null
        ? await AudioDevices.systemDefault(isInput: isInput)
        : AudioDevices.byId(isInput ? lists.inputs : lists.outputs, deviceId);
    if (!mounted) return;
    if (device == null) {
      // No default to point WebRTC at; the next join applies the saved
      // choice. The call's mic must still stop naming the device just
      // un-picked, or every track it makes goes on recording from it.
      if (deviceId == null) {
        _clearSelection(isInput: isInput);
        if (isInput) {
          await context.read<LiveKitCubit>().refreshAudioInput(null);
        }
      }
      return;
    }
    final formats = isInput ? lists.inputFormats : lists.outputFormats;
    if (_refuseUnusable(device, formats)) {
      // The default is still recorded as the choice, with the reason it
      // cannot play shown beside it. Refusing it outright kept the old device
      // saved, with no way back to the default at all.
      if (deviceId == null) _clearSelection(isInput: isInput, keepError: true);
      return;
    }

    try {
      if (isInput) {
        await Hardware.instance.selectAudioInput(device);
      } else {
        await Hardware.instance.selectAudioOutput(device);
      }
    } catch (e) {
      if (!mounted) return;
      final noun = isInput ? 'microphone' : 'output';
      setState(() => _selectionError = 'Could not use that $noun: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _selectionError = null);

    final app = context.read<AppCubit>();
    if (isInput) {
      app.setInputDeviceId(deviceId);
      // The mic track has to be remade naming the device, or the plugin puts
      // it back on the first input as it is made.
      await context.read<LiveKitCubit>().refreshAudioInput(device.deviceId);
    } else {
      // Nothing to rebuild for playout: the call above reaches libwebrtc's
      // SetPlayoutDevice, which restarts it on the new device by itself when
      // something is playing.
      app.setOutputDeviceId(deviceId);
    }
  }

  /// Records a pick made outside a call, where there is nothing to apply it
  /// to: the next join puts it in force. A device that could not be opened is
  /// still refused here, since that join would only skip it.
  void _save(String? deviceId, {required bool isInput}) {
    if (deviceId == null) return _clearSelection(isInput: isInput);
    final lists = _lists.state;
    final device = AudioDevices.byId(
      isInput ? lists.inputs : lists.outputs,
      deviceId,
    );
    if (device == null) return;
    final formats = isInput ? lists.inputFormats : lists.outputFormats;
    if (_refuseUnusable(device, formats)) return;
    setState(() => _selectionError = null);
    final app = context.read<AppCubit>();
    if (isInput) {
      app.setInputDeviceId(deviceId);
    } else {
      app.setOutputDeviceId(deviceId);
    }
  }

  /// Refuses a device whose format WebRTC cannot open, and says why.
  ///
  /// Letting the switch through would not merely fail: playout stops, fails to
  /// reopen, and is not restarted by any later device change, so the call goes
  /// silent until it is rejoined. Windows will convert bit depth for a shared
  /// stream but not channel count, so a device presented as, say, 8 channel
  /// 96 kHz — the usual shape of a virtual device belonging to audio routing
  /// software — has nothing WebRTC can ask it for.
  ///
  /// Returns true when the caller should stop.
  bool _refuseUnusable(MediaDevice device, Map<String, AudioEndpoint> formats) {
    final format = AudioDevices.unusableFormat(formats[device.deviceId]);
    if (format == null) return false;
    setState(() {
      _selectionError =
          'Windows is running ${AudioDevices.labelOf(device)} at $format. '
          'Voice can only open a device with one or two channels at a standard '
          'rate, so switching to it would silence the call. Change its format '
          'under Sound settings → Properties → Advanced, or in the software '
          'that provides it.';
    });
    return true;
  }

  /// Forgets the saved device, so the next join uses the system default.
  void _clearSelection({required bool isInput, bool keepError = false}) {
    final cubit = context.read<AppCubit>();
    if (isInput) {
      cubit.setInputDeviceId(null);
    } else {
      cubit.setOutputDeviceId(null);
    }
    if (!keepError) setState(() => _selectionError = null);
  }

  @override
  Widget build(BuildContext context) {
    // Joining or leaving swaps which list applies (see [AudioDeviceLists.live]); reading it
    // again keeps a pick from going to a device module that is not there.
    return BlocListener<LiveKitCubit, LiveKitState>(
      listenWhen: (a, b) => (a.room == null) != (b.room == null),
      listener: (_, _) => _reload(),
      child: _buildPickers(context),
    );
  }

  Widget _buildPickers(BuildContext context) {
    final lists = context.watch<AudioDeviceListCubit>().state;
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        final error = _selectionError ?? lists.loadError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AudioDevicePicker(
              label: 'Input device',
              icon: Icons.mic_rounded,
              devices: lists.inputs,
              formats: lists.inputFormats,
              selectedDeviceId: appState.inputDeviceId,
              loading: !lists.loaded,
              onChanged: (id) => _select(id, isInput: true),
            ),
            const SizedBox(height: 22),
            AudioDevicePicker(
              label: 'Output device',
              icon: Icons.headset_rounded,
              devices: lists.outputs,
              formats: lists.outputFormats,
              selectedDeviceId: appState.outputDeviceId,
              loading: !lists.loaded,
              onChanged: (id) => _select(id, isInput: false),
            ),
            // A device switch that fails used to do so silently, which is
            // indistinguishable from one that worked and killed the audio.
            if (error != null) ...[
              const SizedBox(height: 12),
              MessageBanner(message: error, kind: MessageBannerKind.error),
            ],
          ],
        );
      },
    );
  }
}
