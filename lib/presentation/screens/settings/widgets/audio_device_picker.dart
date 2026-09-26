import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../../../logic/services/audio_devices.dart';
import '../../../common/app_dropdown.dart';
import '../../../theme/app_text.dart';
import '../../../theme/theme_context.dart';
import 'section_title.dart';

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
  /// A saved id counts only while that device is still present. The picker
  /// used to be Material's dropdown, which asserts when handed a value that
  /// is not among its items, so a stale id from another machine was a crash
  /// rather than a fallback; a missing device still falls back here rather
  /// than showing an id nobody can pick.
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
          AppDropdown<String?>(
            icon: icon,
            value: _displayId,
            options: [
              // Naming no device is a real choice, and the one to land on
              // first. Windows already has an answer, and these lists can be
              // full of virtual endpoints whose names say nothing about where
              // the sound ends up.
              const AppDropdownOption<String?>(
                value: null,
                label: 'System default',
              ),
              // Devices WebRTC cannot open stay on the list and say so, rather
              // than disappearing: they are real devices the user can see in
              // Windows, and the thing that has to change is their format.
              ...devices.map((device) {
                final unusable = AudioDevices.unusableFormat(
                  formats[device.deviceId],
                );
                return AppDropdownOption<String?>(
                  value: device.deviceId,
                  label: unusable == null
                      ? AudioDevices.labelOf(device)
                      : '${AudioDevices.labelOf(device)}  ·  $unusable, '
                            'unsupported',
                );
              }),
            ],
            onChanged: onChanged,
          ),
      ],
    );
  }
}
