import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../../logic/services/audio_devices.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';
import 'audio_device_picker.dart';

/// Section for selecting audio input and output devices.
class AudioDeviceSection extends StatefulWidget {
  final ThemeState themeState;

  const AudioDeviceSection({super.key, required this.themeState});

  @override
  State<AudioDeviceSection> createState() => _AudioDeviceSectionState();
}

class _AudioDeviceSectionState extends State<AudioDeviceSection> {
  List<MediaDevice> _inputDevices = [];
  List<MediaDevice> _outputDevices = [];
  bool _devicesLoading = true;

  /// Kept apart from [_selectionError] so a device-change event, which reloads
  /// the list, cannot wipe the explanation of a choice that was just refused
  /// before it has been read.
  String? _loadError;
  String? _selectionError;

  /// What Windows reports each endpoint's shared format as, keyed by device id.
  /// Empty means nothing is known, and nothing is then refused on its account.
  Map<String, AudioEndpoint> _inputFormats = const {};
  Map<String, AudioEndpoint> _outputFormats = const {};

  StreamSubscription<List<MediaDevice>>? _deviceChangeSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    // Devices used to be read once and never again, so plugging a headset in
    // while this was open left a list that no longer described the machine.
    _deviceChangeSub = Hardware.instance.onDeviceChange.stream.listen((_) {
      _loadDevices();
    });
  }

  @override
  void dispose() {
    _deviceChangeSub?.cancel();
    super.dispose();
  }

  /// Reads the device lists. Deliberately applies nothing.
  ///
  /// Selecting the saved devices here meant simply opening this screen swapped
  /// the device under a playout stream that was already running, which stops
  /// the audio — and the device-change listener runs this again, so each apply
  /// could provoke the next. Joining a channel applies the saved choice, at
  /// the one point where there is a device module to apply it to and no stream
  /// yet to break; after that only an explicit pick applies.
  Future<void> _loadDevices() async {
    try {
      final devices = await AudioDevices.load();
      final inputFormats = await AudioDevices.inputEndpointFormats();
      final outputFormats = await AudioDevices.outputEndpointFormats();
      if (!mounted) return;

      setState(() {
        _inputDevices = devices.inputs;
        _outputDevices = devices.outputs;
        _inputFormats = inputFormats;
        _outputFormats = outputFormats;
        _devicesLoading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _devicesLoading = false;
        _loadError = 'Could not read audio devices: $e';
      });
    }
  }

  /// Applies a picked device, then records it.
  ///
  /// That order matters: recording the choice first meant a device the
  /// platform went on to refuse stayed saved and came back next launch.
  Future<void> _select(String? deviceId, {required bool isInput}) async {
    if (deviceId == null) {
      _clearSelection(isInput: isInput);
      return;
    }
    final device = AudioDevices.byId(
      isInput ? _inputDevices : _outputDevices,
      deviceId,
    );
    if (device == null) return;
    if (_refuseUnusable(device, isInput ? _inputFormats : _outputFormats)) {
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
      // WebRTC binds the capture device when the track is created, so a track
      // already publishing keeps the old microphone until it is rebuilt.
      await context.read<LiveKitCubit>().refreshAudioInput();
    } else {
      // Nothing to rebuild for playout: the call above reaches libwebrtc's
      // SetPlayoutDevice, which restarts it on the new device by itself when
      // something is playing.
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

  /// Forgets the saved device, so the next join does not override the
  /// platform's own choice.
  ///
  /// This does not move a running call back to the default. Doing that needs
  /// the default endpoint's id, which only Windows can supply; reading it
  /// through the Win32 audio interfaces crashed the app, so that is left out
  /// until it can be done and checked properly.
  void _clearSelection({required bool isInput}) {
    final cubit = context.read<AppCubit>();
    if (isInput) {
      cubit.setInputDeviceId(null);
    } else {
      cubit.setOutputDeviceId(null);
    }
    setState(() => _selectionError = null);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        final error = _selectionError ?? _loadError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AudioDevicePicker(
              label: 'Input Device',
              icon: Icons.mic_rounded,
              devices: _inputDevices,
              formats: _inputFormats,
              selectedDeviceId: appState.inputDeviceId,
              loading: _devicesLoading,
              themeState: widget.themeState,
              onChanged: (id) => _select(id, isInput: true),
            ),
            const SizedBox(height: 22),
            AudioDevicePicker(
              label: 'Output Device',
              icon: Icons.headset_rounded,
              devices: _outputDevices,
              formats: _outputFormats,
              selectedDeviceId: appState.outputDeviceId,
              loading: _devicesLoading,
              themeState: widget.themeState,
              onChanged: (id) => _select(id, isInput: false),
            ),
            // A device switch that fails used to do so silently, which is
            // indistinguishable from one that worked and killed the audio.
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: AppText.secondary.copyWith(color: CustomColors.error),
              ),
            ],
          ],
        );
      },
    );
  }
}
