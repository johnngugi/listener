import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_engine/listener_engine.dart';
import 'package:listener_front/src/models/output_device_state.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';

final class OutputDeviceCubit extends Cubit<OutputDeviceState> {
  OutputDeviceCubit(this._engine, this._playback)
    : super(const OutputDeviceState.loading()) {
    unawaited(refresh());
  }

  final PlaybackEngine _engine;
  final PlaybackCubit _playback;

  Future<void> refresh() async {
    emit(
      OutputDeviceState(
        status: OutputDeviceStatus.loading,
        devices: state.devices,
        selectedDeviceId: state.selectedDeviceId,
      ),
    );

    try {
      final devices = List<AudioOutputDevice>.unmodifiable(
        _engine.outputDevices(),
      );
      var selectedDeviceId = state.selectedDeviceId;
      if (selectedDeviceId != null &&
          !devices.any((device) => device.id == selectedDeviceId)) {
        await _playback.switchOutputDevice(null);
        selectedDeviceId = null;
      }

      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.ready,
          devices: devices,
          selectedDeviceId: selectedDeviceId,
        ),
      );
    } catch (error) {
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.error,
          devices: state.devices,
          selectedDeviceId: state.selectedDeviceId,
          errorMessage: 'Unable to load audio outputs: $error',
        ),
      );
    }
  }

  Future<bool> selectDevice(String? deviceId) async {
    if (deviceId == state.selectedDeviceId) return true;

    emit(
      OutputDeviceState(
        status: OutputDeviceStatus.switching,
        devices: state.devices,
        selectedDeviceId: state.selectedDeviceId,
      ),
    );

    try {
      await _playback.switchOutputDevice(deviceId);
    } catch (error) {
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.error,
          devices: state.devices,
          selectedDeviceId: state.selectedDeviceId,
          errorMessage: error.toString(),
        ),
      );
      return false;
    }

    emit(
      OutputDeviceState(
        status: OutputDeviceStatus.ready,
        devices: state.devices,
        selectedDeviceId: deviceId,
      ),
    );
    return true;
  }
}
