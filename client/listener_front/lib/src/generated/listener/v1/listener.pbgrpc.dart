// This is a generated file - do not edit.
//
// Generated from listener/v1/listener.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:grpc/service_api.dart' as $grpc;
import 'package:protobuf/protobuf.dart' as $pb;

import 'listener.pb.dart' as $0;

export 'listener.pb.dart';

@$pb.GrpcServiceName('listener.control.v1.ListenerControl')
class ListenerControlClient extends $grpc.Client {
  /// The hostname for this service.
  static const $core.String defaultHost = '';

  /// OAuth scopes needed for the client.
  static const $core.List<$core.String> oauthScopes = [
    '',
  ];

  ListenerControlClient(super.channel, {super.options, super.interceptors});

  $grpc.ResponseFuture<$0.StartResponse> start(
    $0.StartRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$start, request, options: options);
  }

  $grpc.ResponseFuture<$0.CommandResponse> stop(
    $0.StopRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$stop, request, options: options);
  }

  $grpc.ResponseFuture<$0.CommandResponse> pause(
    $0.PauseRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$pause, request, options: options);
  }

  $grpc.ResponseFuture<$0.CommandResponse> resume(
    $0.ResumeRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$resume, request, options: options);
  }

  $grpc.ResponseFuture<$0.CommandResponse> seek(
    $0.SeekRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$seek, request, options: options);
  }

  $grpc.ResponseFuture<$0.StatusResponse> status(
    $0.StatusRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createUnaryCall(_$status, request, options: options);
  }

  $grpc.ResponseStream<$0.PlaybackEvent> watch(
    $0.WatchRequest request, {
    $grpc.CallOptions? options,
  }) {
    return $createStreamingCall(_$watch, $async.Stream.fromIterable([request]),
        options: options);
  }

  // method descriptors

  static final _$start = $grpc.ClientMethod<$0.StartRequest, $0.StartResponse>(
      '/listener.control.v1.ListenerControl/Start',
      ($0.StartRequest value) => value.writeToBuffer(),
      $0.StartResponse.fromBuffer);
  static final _$stop = $grpc.ClientMethod<$0.StopRequest, $0.CommandResponse>(
      '/listener.control.v1.ListenerControl/Stop',
      ($0.StopRequest value) => value.writeToBuffer(),
      $0.CommandResponse.fromBuffer);
  static final _$pause =
      $grpc.ClientMethod<$0.PauseRequest, $0.CommandResponse>(
          '/listener.control.v1.ListenerControl/Pause',
          ($0.PauseRequest value) => value.writeToBuffer(),
          $0.CommandResponse.fromBuffer);
  static final _$resume =
      $grpc.ClientMethod<$0.ResumeRequest, $0.CommandResponse>(
          '/listener.control.v1.ListenerControl/Resume',
          ($0.ResumeRequest value) => value.writeToBuffer(),
          $0.CommandResponse.fromBuffer);
  static final _$seek = $grpc.ClientMethod<$0.SeekRequest, $0.CommandResponse>(
      '/listener.control.v1.ListenerControl/Seek',
      ($0.SeekRequest value) => value.writeToBuffer(),
      $0.CommandResponse.fromBuffer);
  static final _$status =
      $grpc.ClientMethod<$0.StatusRequest, $0.StatusResponse>(
          '/listener.control.v1.ListenerControl/Status',
          ($0.StatusRequest value) => value.writeToBuffer(),
          $0.StatusResponse.fromBuffer);
  static final _$watch = $grpc.ClientMethod<$0.WatchRequest, $0.PlaybackEvent>(
      '/listener.control.v1.ListenerControl/Watch',
      ($0.WatchRequest value) => value.writeToBuffer(),
      $0.PlaybackEvent.fromBuffer);
}

@$pb.GrpcServiceName('listener.control.v1.ListenerControl')
abstract class ListenerControlServiceBase extends $grpc.Service {
  $core.String get $name => 'listener.control.v1.ListenerControl';

  ListenerControlServiceBase() {
    $addMethod($grpc.ServiceMethod<$0.StartRequest, $0.StartResponse>(
        'Start',
        start_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.StartRequest.fromBuffer(value),
        ($0.StartResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StopRequest, $0.CommandResponse>(
        'Stop',
        stop_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.StopRequest.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.PauseRequest, $0.CommandResponse>(
        'Pause',
        pause_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.PauseRequest.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.ResumeRequest, $0.CommandResponse>(
        'Resume',
        resume_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.ResumeRequest.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.SeekRequest, $0.CommandResponse>(
        'Seek',
        seek_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.SeekRequest.fromBuffer(value),
        ($0.CommandResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.StatusRequest, $0.StatusResponse>(
        'Status',
        status_Pre,
        false,
        false,
        ($core.List<$core.int> value) => $0.StatusRequest.fromBuffer(value),
        ($0.StatusResponse value) => value.writeToBuffer()));
    $addMethod($grpc.ServiceMethod<$0.WatchRequest, $0.PlaybackEvent>(
        'Watch',
        watch_Pre,
        false,
        true,
        ($core.List<$core.int> value) => $0.WatchRequest.fromBuffer(value),
        ($0.PlaybackEvent value) => value.writeToBuffer()));
  }

  $async.Future<$0.StartResponse> start_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.StartRequest> $request) async {
    return start($call, await $request);
  }

  $async.Future<$0.StartResponse> start(
      $grpc.ServiceCall call, $0.StartRequest request);

  $async.Future<$0.CommandResponse> stop_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.StopRequest> $request) async {
    return stop($call, await $request);
  }

  $async.Future<$0.CommandResponse> stop(
      $grpc.ServiceCall call, $0.StopRequest request);

  $async.Future<$0.CommandResponse> pause_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.PauseRequest> $request) async {
    return pause($call, await $request);
  }

  $async.Future<$0.CommandResponse> pause(
      $grpc.ServiceCall call, $0.PauseRequest request);

  $async.Future<$0.CommandResponse> resume_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.ResumeRequest> $request) async {
    return resume($call, await $request);
  }

  $async.Future<$0.CommandResponse> resume(
      $grpc.ServiceCall call, $0.ResumeRequest request);

  $async.Future<$0.CommandResponse> seek_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.SeekRequest> $request) async {
    return seek($call, await $request);
  }

  $async.Future<$0.CommandResponse> seek(
      $grpc.ServiceCall call, $0.SeekRequest request);

  $async.Future<$0.StatusResponse> status_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.StatusRequest> $request) async {
    return status($call, await $request);
  }

  $async.Future<$0.StatusResponse> status(
      $grpc.ServiceCall call, $0.StatusRequest request);

  $async.Stream<$0.PlaybackEvent> watch_Pre(
      $grpc.ServiceCall $call, $async.Future<$0.WatchRequest> $request) async* {
    yield* watch($call, await $request);
  }

  $async.Stream<$0.PlaybackEvent> watch(
      $grpc.ServiceCall call, $0.WatchRequest request);
}
