import 'package:equatable/equatable.dart';
import 'package:listener_engine/listener_engine.dart';

enum OutputDeviceStatus { loading, ready, switching, error }

final class OutputDeviceState extends Equatable {
  const OutputDeviceState({
    required this.status,
    required this.devices,
    required this.selectedDeviceId,
    required this.exclusiveMode,
    this.errorMessage,
  });

  const OutputDeviceState.loading()
    : status = OutputDeviceStatus.loading,
      devices = const [],
      selectedDeviceId = null,
      exclusiveMode = false,
      errorMessage = null;

  final OutputDeviceStatus status;
  final List<AudioOutputDevice> devices;
  final String? selectedDeviceId;
  final bool exclusiveMode;
  final String? errorMessage;

  AudioOutputDevice? get selectedDevice {
    final selectedId = selectedDeviceId;
    if (selectedId == null) return null;
    for (final device in devices) {
      if (device.id == selectedId) return device;
    }
    return null;
  }

  AudioOutputDevice? get effectiveDevice {
    final selected = selectedDevice;
    if (selected != null) return selected;
    for (final device in devices) {
      if (device.isDefault) return device;
    }
    return null;
  }

  bool get supportsExclusiveMode =>
      effectiveDevice?.capabilities.supportsExclusiveMode ?? false;

  @override
  List<Object?> get props => [
    status,
    devices,
    selectedDeviceId,
    exclusiveMode,
    errorMessage,
  ];
}
