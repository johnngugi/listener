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
        exclusiveMode: state.exclusiveMode,
      ),
    );

    try {
      final devices = List<AudioOutputDevice>.unmodifiable(
        _engine.outputDevices(),
      );
      var selectedDeviceId = state.selectedDeviceId;
      var exclusiveMode = state.exclusiveMode;
      if (selectedDeviceId != null &&
          !devices.any((device) => device.id == selectedDeviceId)) {
        if (exclusiveMode && !_supportsExclusiveMode(devices, null)) {
          await _playback.configureOutput(const AudioOutputConfiguration());
          exclusiveMode = false;
          emit(
            OutputDeviceState(
              status: OutputDeviceStatus.loading,
              devices: devices,
              selectedDeviceId: selectedDeviceId,
              exclusiveMode: false,
            ),
          );
        }
        await _playback.switchOutputDevice(null);
        selectedDeviceId = null;
      } else if (exclusiveMode &&
          !_supportsExclusiveMode(devices, selectedDeviceId)) {
        await _playback.configureOutput(const AudioOutputConfiguration());
        exclusiveMode = false;
        emit(
          OutputDeviceState(
            status: OutputDeviceStatus.loading,
            devices: devices,
            selectedDeviceId: selectedDeviceId,
            exclusiveMode: false,
          ),
        );
      }

      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.ready,
          devices: devices,
          selectedDeviceId: selectedDeviceId,
          exclusiveMode: exclusiveMode,
        ),
      );
    } catch (error) {
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.error,
          devices: state.devices,
          selectedDeviceId: state.selectedDeviceId,
          exclusiveMode: state.exclusiveMode,
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
        exclusiveMode: state.exclusiveMode,
      ),
    );

    try {
      var exclusiveMode = state.exclusiveMode;
      if (exclusiveMode && !_supportsExclusiveMode(state.devices, deviceId)) {
        await _playback.configureOutput(const AudioOutputConfiguration());
        exclusiveMode = false;
        emit(
          OutputDeviceState(
            status: OutputDeviceStatus.switching,
            devices: state.devices,
            selectedDeviceId: state.selectedDeviceId,
            exclusiveMode: false,
          ),
        );
      }
      await _playback.switchOutputDevice(deviceId);
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.ready,
          devices: state.devices,
          selectedDeviceId: deviceId,
          exclusiveMode: exclusiveMode,
        ),
      );
    } catch (error) {
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.error,
          devices: state.devices,
          selectedDeviceId: state.selectedDeviceId,
          exclusiveMode: state.exclusiveMode,
          errorMessage: error.toString(),
        ),
      );
      return false;
    }

    return true;
  }

  Future<bool> setExclusiveMode(bool enabled) async {
    if (enabled == state.exclusiveMode) return true;
    if (enabled && !state.supportsExclusiveMode) return false;

    emit(
      OutputDeviceState(
        status: OutputDeviceStatus.switching,
        devices: state.devices,
        selectedDeviceId: state.selectedDeviceId,
        exclusiveMode: state.exclusiveMode,
      ),
    );

    try {
      await _playback.configureOutput(
        AudioOutputConfiguration(exclusiveMode: enabled),
      );
    } catch (error) {
      emit(
        OutputDeviceState(
          status: OutputDeviceStatus.error,
          devices: state.devices,
          selectedDeviceId: state.selectedDeviceId,
          exclusiveMode: state.exclusiveMode,
          errorMessage: error.toString(),
        ),
      );
      return false;
    }

    emit(
      OutputDeviceState(
        status: OutputDeviceStatus.ready,
        devices: state.devices,
        selectedDeviceId: state.selectedDeviceId,
        exclusiveMode: enabled,
      ),
    );
    return true;
  }

  bool _supportsExclusiveMode(
    List<AudioOutputDevice> devices,
    String? selectedDeviceId,
  ) {
    for (final device in devices) {
      if ((selectedDeviceId == null && device.isDefault) ||
          device.id == selectedDeviceId) {
        return device.capabilities.supportsExclusiveMode;
      }
    }
    return false;
  }
}
