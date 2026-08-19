import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/cubits/app/app_cubit.dart';
import '../../../../logic/cubits/livekit/livekit_cubit.dart';
import '../../../../logic/services/audio_devices.dart';
import 'device_dropdown.dart';
import 'section_title.dart';
import '../../../../logic/cubits/theme/theme_cubit.dart';
import '../../../theme/app_text.dart';
import '../../../theme/custom_colors.dart';

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
  String? _error;

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

  Future<void> _loadDevices() async {
    try {
      await AudioDevices.debugDump();

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
        _error = null;
      });

      // Reading the list must not reselect anything. Applying the saved
      // devices here meant simply opening this screen swapped the device under
      // a playout stream that was already running, which stops the audio — and
      // the device-change listener runs this again, so each apply could
      // provoke the next. Startup applies the saved choice once, before there
      // is any stream to break; after that only an explicit pick applies.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _devicesLoading = false;
        _error = 'Could not read audio devices: $e';
      });
    }
  }

  Future<void> _selectInputDevice(String? deviceId) async {
    if (deviceId == null) {
      await _clearSelection(isInput: true);
      return;
    }
    final device = _deviceById(_inputDevices, deviceId);
    if (device == null) return;
    if (_refuseUnusable(device, _inputFormats)) return;
    // Save only what was actually applied. Recording the choice first meant a
    // device the platform then refused stayed saved and came back next launch.
    try {
      await Hardware.instance.selectAudioInput(device);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not use that microphone: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    context.read<AppCubit>().setInputDeviceId(deviceId);
    await context.read<LiveKitCubit>().refreshAudioInput();
  }

  Future<void> _selectOutputDevice(String? deviceId) async {
    if (deviceId == null) {
      await _clearSelection(isInput: false);
      return;
    }
    final device = _deviceById(_outputDevices, deviceId);
    if (device == null) return;
    if (_refuseUnusable(device, _outputFormats)) return;
    try {
      await Hardware.instance.selectAudioOutput(device);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not use that output: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _error = null);
    // Nothing to rebuild afterwards: the call above reaches libwebrtc's
    // SetPlayoutDevice, which restarts playout on the new device by itself
    // when something is playing.
    context.read<AppCubit>().setOutputDeviceId(deviceId);
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
      _error =
          'Windows is running ${_deviceLabel(device)} at $format. Voice can '
          'only open a device with one or two channels at a standard rate, so '
          'switching to it would silence the call. Change its format under '
          'Sound settings → Properties → Advanced, or in the software that '
          'provides it.';
    });
    return true;
  }

  String _deviceLabel(MediaDevice device) =>
      device.label.isEmpty ? 'Unknown' : device.label;

  /// Forgets the saved device, so the next start does not override the
  /// platform's own choice.
  ///
  /// This does not move a running call back to the default. Doing that needs
  /// the default endpoint's id, which only Windows can supply; reading it
  /// through the Win32 audio interfaces crashed the app, so that is left out
  /// until it can be done and checked properly.
  Future<void> _clearSelection({required bool isInput}) async {
    final cubit = context.read<AppCubit>();
    if (isInput) {
      cubit.setInputDeviceId(null);
    } else {
      cubit.setOutputDeviceId(null);
    }
    setState(() => _error = null);
  }

  /// The device with this id, or null.
  ///
  /// There is deliberately no "or the first one" fallback here. That turned an
  /// id this list does not hold into a silent switch to an unrelated device,
  /// which is worse than doing nothing and much harder to notice.
  MediaDevice? _deviceById(List<MediaDevice> devices, String? deviceId) {
    if (deviceId == null) return null;
    return devices.cast<MediaDevice?>().firstWhere(
      (d) => d?.deviceId == deviceId,
      orElse: () => null,
    );
  }

  /// The id to show in the dropdown, or null for the system default entry.
  ///
  /// A saved id counts only while that device is still present: [DeviceDropdown]
  /// wraps a [DropdownButton], which asserts when handed a value that is not
  /// among its items, so a stale id from another machine was a crash rather
  /// than a fallback.
  ///
  /// With nothing saved this shows the system default rather than naming a
  /// device. It used to fall back to the first entry in the list, which
  /// asserted a selection that had never been applied — and on a machine with
  /// virtual audio devices the first output happened to be one called
  /// "SteelSeries Sonar - Microphone", so the output picker appeared to be set
  /// to a microphone while the platform was quietly using its own default.
  String? _displayId(List<MediaDevice> devices, String? savedId) =>
      _deviceById(devices, savedId) != null ? savedId : null;

  Widget _buildDeviceDropdown({
    required String label,
    required IconData icon,
    required List<MediaDevice> devices,
    required Map<String, AudioEndpoint> formats,
    required String? selectedDeviceId,
    required ValueChanged<String?> onChanged,
  }) {
    final themeState = widget.themeState;
    final effectiveId = _displayId(devices, selectedDeviceId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: label, themeState: themeState),
        const SizedBox(height: 10),
        if (_devicesLoading || devices.isEmpty)
          Text(
            _devicesLoading ? 'Loading devices…' : 'No devices found',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          )
        else
          DeviceDropdown<String>(
            icon: icon,
            value: effectiveId,
            themeState: themeState,
            items: [
              // Naming no device is a real choice, and the one to land on
              // first. Windows already has an answer, and these lists can be
              // full of virtual endpoints whose names say nothing about where
              // the sound ends up.
              const DropdownMenuItem<String>(
                value: null,
                child: Text('System Default', overflow: TextOverflow.ellipsis),
              ),
              // Devices WebRTC cannot open stay on the list and say so, rather
              // than disappearing: they are real devices the user can see in
              // Windows, and the thing that has to change is their format.
              ...devices.map((device) {
                final unusable = AudioDevices.unusableFormat(
                  formats[device.deviceId],
                );
                return DropdownMenuItem<String>(
                  value: device.deviceId,
                  child: Text(
                    unusable == null
                        ? _deviceLabel(device)
                        : '${_deviceLabel(device)}  ·  $unusable, unsupported',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: onChanged,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppCubit, AppState>(
      builder: (context, appState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDeviceDropdown(
              label: 'Input Device',
              icon: Icons.mic_rounded,
              devices: _inputDevices,
              formats: _inputFormats,
              selectedDeviceId: appState.inputDeviceId,
              onChanged: _selectInputDevice,
            ),
            const SizedBox(height: 22),
            _buildDeviceDropdown(
              label: 'Output Device',
              icon: Icons.headset_rounded,
              devices: _outputDevices,
              formats: _outputFormats,
              selectedDeviceId: appState.outputDeviceId,
              onChanged: _selectOutputDevice,
            ),
            // A device switch that fails used to do so silently, which is
            // indistinguishable from one that worked and killed the audio.
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: AppText.secondary.copyWith(color: CustomColors.error),
              ),
            ],
          ],
        );
      },
    );
  }
}
