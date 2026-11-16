import 'package:livekit_client/livekit_client.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../data/classes/sound_outputs.dart';
import '../../../../logic/services/audio_devices.dart';
import '../../../common/advanced_settings.dart';
import 'audio_device_picker.dart';

/// Calls, streams and dings each on a device of their own, behind a fold
/// under the output picker.
///
/// For somebody whose outputs each carry their own processing — a media
/// device with its EQ, a chat device with another — so a watched share's
/// sound can go with their music while voices stay on the headset. Each
/// starts on "Same as output", so the fold changes nothing until a choice is
/// made in it. Which sound belongs to which kind is [SoundKind]'s.
class SoundOutputPickers extends StatefulWidget {
  final List<MediaDevice> devices;
  final Map<String, AudioEndpoint> formats;
  final SoundOutputs choices;
  final bool loading;
  final void Function(SoundKind kind, String? choice) onChanged;

  const SoundOutputPickers({
    super.key,
    required this.devices,
    required this.formats,
    required this.choices,
    required this.loading,
    required this.onChanged,
  });

  @override
  State<SoundOutputPickers> createState() => _SoundOutputPickersState();
}

class _SoundOutputPickersState extends State<SoundOutputPickers> {
  /// Open from the start when something is already split off, so the main
  /// picker is never the whole story without saying so.
  late bool _open = widget.choices.isSplit;

  static const _labels = {
    SoundKind.calls: 'Calls and soundboard',
    SoundKind.streams: 'Streams',
    SoundKind.dings: 'Sounds',
  };

  static const _icons = {
    SoundKind.calls: Icons.call_rounded,
    SoundKind.streams: Icons.cast_rounded,
    SoundKind.dings: Icons.notifications_rounded,
  };

  @override
  Widget build(BuildContext context) {
    return AdvancedSettings(
      label: 'Separate devices',
      open: _open,
      onToggle: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 18,
        children: [
          for (final kind in SoundKind.values)
            AudioDevicePicker(
              label: _labels[kind]!,
              icon: _icons[kind]!,
              devices: widget.devices,
              formats: widget.formats,
              selectedDeviceId: widget.choices.choiceFor(kind),
              loading: widget.loading,
              followLabel: 'Same as output device',
              onChanged: (choice) => widget.onChanged(kind, choice),
            ),
        ],
      ),
    );
  }
}
