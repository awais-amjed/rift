import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/services/audio_devices.dart';
import '../../../theme/app_text.dart';
import 'device_dropdown.dart';
import 'section_title.dart';
import '../../../theme/theme_context.dart';

/// One labelled dropdown of audio devices — input or output.
///
/// Purely how the list is drawn: the section above it owns which devices there
/// are, what is saved, and what happens when the choice changes.
class AudioDevicePicker extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<MediaDevice> devices;

  /// What Windows reports each endpoint's shared format as, keyed by device id.
  /// Empty means nothing is known, and nothing is then marked on its account.
  final Map<String, AudioEndpoint> formats;

  final String? selectedDeviceId;
  final bool loading;
  final ValueChanged<String?> onChanged;

  const AudioDevicePicker({
    super.key,
    required this.label,
    required this.icon,
    required this.devices,
    required this.formats,
    required this.selectedDeviceId,
    required this.loading,
    required this.onChanged,
  });

  /// The id to show, or null for the system-default entry.
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
  String? get _displayId => AudioDevices.byId(devices, selectedDeviceId) != null
      ? selectedDeviceId
      : null;

  @override
  Widget build(BuildContext context) {
    final themeState = context.theme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(label: label),
        const SizedBox(height: 10),
        if (loading || devices.isEmpty)
          Text(
            loading ? 'Loading devices…' : 'No devices found',
            style: AppText.secondary.copyWith(color: themeState.textTertiary),
          )
        else
          DeviceDropdown<String>(
            icon: icon,
            value: _displayId,

            items: [
              // Naming no device is a real choice, and the one to land on
              // first. Windows already has an answer, and these lists can be
              // full of virtual endpoints whose names say nothing about where
              // the sound ends up.
              const DropdownMenuItem<String>(
                value: null,
                child: Text('System default', overflow: TextOverflow.ellipsis),
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
                        ? AudioDevices.labelOf(device)
                        : '${AudioDevices.labelOf(device)}  ·  $unusable, '
                              'unsupported',
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
}
