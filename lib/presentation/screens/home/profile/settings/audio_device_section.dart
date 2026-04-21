import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../../../logic/cubits/app/app_cubit.dart';
import '../../../../../../logic/cubits/theme/theme_cubit.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    try {
      final inputFuture = Hardware.instance.enumerateDevices(type: 'audioinput');
      final outputFuture = Hardware.instance.enumerateDevices(type: 'audiooutput');

      final results = await Future.wait([inputFuture, outputFuture]);

      if (mounted) {
        setState(() {
          _inputDevices = results[0];
          _outputDevices = results[1];
          _devicesLoading = false;
        });

        // Apply saved devices on load
        final appState = context.read<AppCubit>().state;
        
        // Apply saved input device
        if (appState.inputDeviceId != null) {
          final inputDevice = _inputDevices.cast<MediaDevice?>().firstWhere(
            (d) => d?.deviceId == appState.inputDeviceId,
            orElse: () => null,
          );
          if (inputDevice != null) {
            try {
              await Hardware.instance.selectAudioInput(inputDevice);
            } catch (_) {}
          }
        }

        // Apply saved output device
        if (appState.outputDeviceId != null) {
          final outputDevice = _outputDevices.cast<MediaDevice?>().firstWhere(
            (d) => d?.deviceId == appState.outputDeviceId,
            orElse: () => null,
          );
          if (outputDevice != null) {
            try {
              await Hardware.instance.selectAudioOutput(outputDevice);
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _devicesLoading = false);
    }
  }

  Future<void> _selectInputDevice(String? deviceId) async {
    context.read<AppCubit>().setInputDeviceId(deviceId);
    if (deviceId == null) return;
    final device = _inputDevices.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => _inputDevices.first,
    );
    try {
      await Hardware.instance.selectAudioInput(device);
    } catch (_) {}
  }

  Future<void> _selectOutputDevice(String? deviceId) async {
    context.read<AppCubit>().setOutputDeviceId(deviceId);
    if (deviceId == null) return;
    final device = _outputDevices.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => _outputDevices.first,
    );
    try {
      await Hardware.instance.selectAudioOutput(device);
    } catch (_) {}
  }

  Widget _buildDeviceDropdown({
    required String label,
    required List<MediaDevice> devices,
    required String? selectedDeviceId,
    required ValueChanged<String?> onChanged,
  }) {
    final themeState = widget.themeState;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: themeState.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (_devicesLoading)
          Text(
            'Loading devices...',
            style: TextStyle(
              color: themeState.textTertiary,
              fontSize: 12,
            ),
          )
        else if (devices.isEmpty)
          Text(
            'No devices found',
            style: TextStyle(
              color: themeState.textTertiary,
              fontSize: 12,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: themeState.bgSecondary,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: themeState.borderPrimary),
            ),
            child: DropdownButton<String>(
              value: selectedDeviceId,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: themeState.bgSecondary,
              style: TextStyle(
                color: themeState.textPrimary,
                fontSize: 13,
              ),
              items: devices
                  .map((device) => DropdownMenuItem<String>(
                        value: device.deviceId,
                        child: Text(
                          device.label.isEmpty ? 'Unknown' : device.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: onChanged,
            ),
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
              devices: _inputDevices,
              selectedDeviceId: appState.inputDeviceId,
              onChanged: _selectInputDevice,
            ),
            const SizedBox(height: 24),
            _buildDeviceDropdown(
              label: 'Output Device',
              devices: _outputDevices,
              selectedDeviceId: appState.outputDeviceId,
              onChanged: _selectOutputDevice,
            ),
          ],
        );
      },
    );
  }
}

