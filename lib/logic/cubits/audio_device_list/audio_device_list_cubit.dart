import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';

import '../../services/audio_devices.dart';

part 'audio_device_list_state.dart';

/// The audio devices the settings pickers last read, kept while Rift runs.
///
/// Each open of Voice & audio used to start from nothing, so both pickers read
/// "Loading devices…" for a moment and everything under them moved down when
/// the lists landed. Kept here, a reopen draws the last lists at once while
/// [load] reads them again.
class AudioDeviceListCubit extends Cubit<AudioDeviceLists> {
  AudioDeviceListCubit() : super(const AudioDeviceLists());

  /// Counts reads, so one that started earlier and answers later cannot put
  /// back the lists a newer read replaced.
  int _reads = 0;

  /// Reads the device lists. Deliberately applies nothing.
  ///
  /// Selecting the saved devices here meant simply opening Settings swapped
  /// the device under a playout stream that was already running, which stops
  /// the audio — and a device change reads the lists again, so each apply
  /// could provoke the next. Joining a channel applies the saved choice, at
  /// the one point where there is a device module to apply it to and no
  /// stream yet to break; after that only an explicit pick applies.
  Future<void> load() async {
    final read = ++_reads;
    try {
      final devices = await AudioDevices.choices();
      final inputFormats = await AudioDevices.inputEndpointFormats();
      final outputFormats = await AudioDevices.outputEndpointFormats();
      if (read != _reads || isClosed) return;
      emit(
        AudioDeviceLists(
          inputs: devices.inputs,
          outputs: devices.outputs,
          live: devices.live,
          inputFormats: inputFormats,
          outputFormats: outputFormats,
          loaded: true,
        ),
      );
    } catch (e) {
      if (read != _reads || isClosed) return;
      emit(
        state.copyWith(
          loaded: true,
          loadError: 'Could not read audio devices: $e',
        ),
      );
    }
  }
}
