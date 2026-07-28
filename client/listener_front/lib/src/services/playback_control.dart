import 'package:grpc/grpc.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as control;

const _controlCallTimeout = Duration(seconds: 5);

abstract interface class PlaybackControl {
  Future<control.StartResponse> start(control.StartRequest request);

  Future<control.CommandResponse> stop(control.StopRequest request);

  Future<control.CommandResponse> pause(control.PauseRequest request);

  Future<control.CommandResponse> resume(control.ResumeRequest request);
}

final class GrpcPlaybackControl implements PlaybackControl {
  const GrpcPlaybackControl(this._client);

  final control.ListenerControlClient _client;

  @override
  Future<control.StartResponse> start(control.StartRequest request) {
    return _client.start(
      request,
      options: CallOptions(timeout: _controlCallTimeout),
    );
  }

  @override
  Future<control.CommandResponse> stop(control.StopRequest request) {
    return _client.stop(
      request,
      options: CallOptions(timeout: _controlCallTimeout),
    );
  }

  @override
  Future<control.CommandResponse> pause(control.PauseRequest request) {
    return _client.pause(
      request,
      options: CallOptions(timeout: _controlCallTimeout),
    );
  }

  @override
  Future<control.CommandResponse> resume(control.ResumeRequest request) {
    return _client.resume(
      request,
      options: CallOptions(timeout: _controlCallTimeout),
    );
  }
}
