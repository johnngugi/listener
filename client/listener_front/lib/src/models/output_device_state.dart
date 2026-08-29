import 'package:equatable/equatable.dart';
import 'package:listener_engine/listener_engine.dart';

enum OutputDeviceStatus { loading, ready, switching, error }

final class OutputDeviceState extends Equatable {
  const OutputDeviceState({
    required this.status,
    required this.devices,
    required this.selectedDeviceId,
    this.errorMessage,
  });

  const OutputDeviceState.loading()
    : status = OutputDeviceStatus.loading,
      devices = const [],
      selectedDeviceId = null,
      errorMessage = null;

  final OutputDeviceStatus status;
  final List<AudioOutputDevice> devices;
  final String? selectedDeviceId;
  final String? errorMessage;

  AudioOutputDevice? get selectedDevice {
    final selectedId = selectedDeviceId;
    if (selectedId == null) return null;
    for (final device in devices) {
      if (device.id == selectedId) return device;
    }
    return null;
  }

  @override
  List<Object?> get props => [status, devices, selectedDeviceId, errorMessage];
}
