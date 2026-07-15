// This is a generated file - do not edit.
//
// Generated from listener/v1/listener.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use playbackStateDescriptor instead')
const PlaybackState$json = {
  '1': 'PlaybackState',
  '2': [
    {'1': 'PLAYBACK_STATE_UNSPECIFIED', '2': 0},
    {'1': 'PLAYBACK_STATE_IDLE', '2': 1},
    {'1': 'PLAYBACK_STATE_STARTING', '2': 2},
    {'1': 'PLAYBACK_STATE_PLAYING', '2': 3},
    {'1': 'PLAYBACK_STATE_PAUSED', '2': 4},
    {'1': 'PLAYBACK_STATE_STOPPED', '2': 5},
    {'1': 'PLAYBACK_STATE_ENDED', '2': 6},
    {'1': 'PLAYBACK_STATE_ERROR', '2': 7},
  ],
};

/// Descriptor for `PlaybackState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List playbackStateDescriptor = $convert.base64Decode(
    'Cg1QbGF5YmFja1N0YXRlEh4KGlBMQVlCQUNLX1NUQVRFX1VOU1BFQ0lGSUVEEAASFwoTUExBWU'
    'JBQ0tfU1RBVEVfSURMRRABEhsKF1BMQVlCQUNLX1NUQVRFX1NUQVJUSU5HEAISGgoWUExBWUJB'
    'Q0tfU1RBVEVfUExBWUlORxADEhkKFVBMQVlCQUNLX1NUQVRFX1BBVVNFRBAEEhoKFlBMQVlCQU'
    'NLX1NUQVRFX1NUT1BQRUQQBRIYChRQTEFZQkFDS19TVEFURV9FTkRFRBAGEhgKFFBMQVlCQUNL'
    'X1NUQVRFX0VSUk9SEAc=');

@$core.Deprecated('Use listTracksRequestDescriptor instead')
const ListTracksRequest$json = {
  '1': 'ListTracksRequest',
  '2': [
    {'1': 'page_size', '3': 1, '4': 1, '5': 13, '10': 'pageSize'},
    {'1': 'page_token', '3': 2, '4': 1, '5': 9, '10': 'pageToken'},
  ],
};

/// Descriptor for `ListTracksRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTracksRequestDescriptor = $convert.base64Decode(
    'ChFMaXN0VHJhY2tzUmVxdWVzdBIbCglwYWdlX3NpemUYASABKA1SCHBhZ2VTaXplEh0KCnBhZ2'
    'VfdG9rZW4YAiABKAlSCXBhZ2VUb2tlbg==');

@$core.Deprecated('Use listTracksResponseDescriptor instead')
const ListTracksResponse$json = {
  '1': 'ListTracksResponse',
  '2': [
    {
      '1': 'tracks',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.listener.control.v1.Track',
      '10': 'tracks'
    },
    {'1': 'next_page_token', '3': 2, '4': 1, '5': 9, '10': 'nextPageToken'},
    {'1': 'total_size', '3': 3, '4': 1, '5': 4, '10': 'totalSize'},
  ],
};

/// Descriptor for `ListTracksResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List listTracksResponseDescriptor = $convert.base64Decode(
    'ChJMaXN0VHJhY2tzUmVzcG9uc2USMgoGdHJhY2tzGAEgAygLMhoubGlzdGVuZXIuY29udHJvbC'
    '52MS5UcmFja1IGdHJhY2tzEiYKD25leHRfcGFnZV90b2tlbhgCIAEoCVINbmV4dFBhZ2VUb2tl'
    'bhIdCgp0b3RhbF9zaXplGAMgASgEUgl0b3RhbFNpemU=');

@$core.Deprecated('Use trackDescriptor instead')
const Track$json = {
  '1': 'Track',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 3, '10': 'id'},
    {'1': 'path', '3': 2, '4': 1, '5': 9, '10': 'path'},
    {'1': 'size_bytes', '3': 3, '4': 1, '5': 4, '10': 'sizeBytes'},
    {
      '1': 'modified_unix_nanos',
      '3': 4,
      '4': 1,
      '5': 3,
      '10': 'modifiedUnixNanos'
    },
  ],
};

/// Descriptor for `Track`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List trackDescriptor = $convert.base64Decode(
    'CgVUcmFjaxIOCgJpZBgBIAEoA1ICaWQSEgoEcGF0aBgCIAEoCVIEcGF0aBIdCgpzaXplX2J5dG'
    'VzGAMgASgEUglzaXplQnl0ZXMSLgoTbW9kaWZpZWRfdW5peF9uYW5vcxgEIAEoA1IRbW9kaWZp'
    'ZWRVbml4TmFub3M=');

@$core.Deprecated('Use startRequestDescriptor instead')
const StartRequest$json = {
  '1': 'StartRequest',
  '2': [
    {'1': 'media_path', '3': 1, '4': 1, '5': 9, '10': 'mediaPath'},
    {'1': 'start_frame', '3': 2, '4': 1, '5': 4, '10': 'startFrame'},
  ],
};

/// Descriptor for `StartRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startRequestDescriptor = $convert.base64Decode(
    'CgxTdGFydFJlcXVlc3QSHQoKbWVkaWFfcGF0aBgBIAEoCVIJbWVkaWFQYXRoEh8KC3N0YXJ0X2'
    'ZyYW1lGAIgASgEUgpzdGFydEZyYW1l');

@$core.Deprecated('Use startResponseDescriptor instead')
const StartResponse$json = {
  '1': 'StartResponse',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.listener.control.v1.PlaybackState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `StartResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startResponseDescriptor = $convert.base64Decode(
    'Cg1TdGFydFJlc3BvbnNlEh8KC3BsYXliYWNrX2lkGAEgASgJUgpwbGF5YmFja0lkEjgKBXN0YX'
    'RlGAIgASgOMiIubGlzdGVuZXIuY29udHJvbC52MS5QbGF5YmFja1N0YXRlUgVzdGF0ZQ==');

@$core.Deprecated('Use stopRequestDescriptor instead')
const StopRequest$json = {
  '1': 'StopRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
  ],
};

/// Descriptor for `StopRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stopRequestDescriptor = $convert.base64Decode(
    'CgtTdG9wUmVxdWVzdBIfCgtwbGF5YmFja19pZBgBIAEoCVIKcGxheWJhY2tJZA==');

@$core.Deprecated('Use pauseRequestDescriptor instead')
const PauseRequest$json = {
  '1': 'PauseRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
  ],
};

/// Descriptor for `PauseRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pauseRequestDescriptor = $convert.base64Decode(
    'CgxQYXVzZVJlcXVlc3QSHwoLcGxheWJhY2tfaWQYASABKAlSCnBsYXliYWNrSWQ=');

@$core.Deprecated('Use resumeRequestDescriptor instead')
const ResumeRequest$json = {
  '1': 'ResumeRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
  ],
};

/// Descriptor for `ResumeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List resumeRequestDescriptor = $convert.base64Decode(
    'Cg1SZXN1bWVSZXF1ZXN0Eh8KC3BsYXliYWNrX2lkGAEgASgJUgpwbGF5YmFja0lk');

@$core.Deprecated('Use seekRequestDescriptor instead')
const SeekRequest$json = {
  '1': 'SeekRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
    {'1': 'frame', '3': 2, '4': 1, '5': 4, '10': 'frame'},
  ],
};

/// Descriptor for `SeekRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List seekRequestDescriptor = $convert.base64Decode(
    'CgtTZWVrUmVxdWVzdBIfCgtwbGF5YmFja19pZBgBIAEoCVIKcGxheWJhY2tJZBIUCgVmcmFtZR'
    'gCIAEoBFIFZnJhbWU=');

@$core.Deprecated('Use statusRequestDescriptor instead')
const StatusRequest$json = {
  '1': 'StatusRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
  ],
};

/// Descriptor for `StatusRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusRequestDescriptor = $convert.base64Decode(
    'Cg1TdGF0dXNSZXF1ZXN0Eh8KC3BsYXliYWNrX2lkGAEgASgJUgpwbGF5YmFja0lk');

@$core.Deprecated('Use watchRequestDescriptor instead')
const WatchRequest$json = {
  '1': 'WatchRequest',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
  ],
};

/// Descriptor for `WatchRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List watchRequestDescriptor = $convert.base64Decode(
    'CgxXYXRjaFJlcXVlc3QSHwoLcGxheWJhY2tfaWQYASABKAlSCnBsYXliYWNrSWQ=');

@$core.Deprecated('Use commandResponseDescriptor instead')
const CommandResponse$json = {
  '1': 'CommandResponse',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.listener.control.v1.PlaybackState',
      '10': 'state'
    },
  ],
};

/// Descriptor for `CommandResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandResponseDescriptor = $convert.base64Decode(
    'Cg9Db21tYW5kUmVzcG9uc2USHwoLcGxheWJhY2tfaWQYASABKAlSCnBsYXliYWNrSWQSOAoFc3'
    'RhdGUYAiABKA4yIi5saXN0ZW5lci5jb250cm9sLnYxLlBsYXliYWNrU3RhdGVSBXN0YXRl');

@$core.Deprecated('Use statusResponseDescriptor instead')
const StatusResponse$json = {
  '1': 'StatusResponse',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.listener.control.v1.PlaybackState',
      '10': 'state'
    },
    {'1': 'media_path', '3': 3, '4': 1, '5': 9, '10': 'mediaPath'},
    {'1': 'current_frame', '3': 4, '4': 1, '5': 4, '10': 'currentFrame'},
    {'1': 'generation_id', '3': 5, '4': 1, '5': 4, '10': 'generationId'},
  ],
};

/// Descriptor for `StatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusResponseDescriptor = $convert.base64Decode(
    'Cg5TdGF0dXNSZXNwb25zZRIfCgtwbGF5YmFja19pZBgBIAEoCVIKcGxheWJhY2tJZBI4CgVzdG'
    'F0ZRgCIAEoDjIiLmxpc3RlbmVyLmNvbnRyb2wudjEuUGxheWJhY2tTdGF0ZVIFc3RhdGUSHQoK'
    'bWVkaWFfcGF0aBgDIAEoCVIJbWVkaWFQYXRoEiMKDWN1cnJlbnRfZnJhbWUYBCABKARSDGN1cn'
    'JlbnRGcmFtZRIjCg1nZW5lcmF0aW9uX2lkGAUgASgEUgxnZW5lcmF0aW9uSWQ=');

@$core.Deprecated('Use playbackEventDescriptor instead')
const PlaybackEvent$json = {
  '1': 'PlaybackEvent',
  '2': [
    {'1': 'playback_id', '3': 1, '4': 1, '5': 9, '10': 'playbackId'},
    {
      '1': 'state',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.listener.control.v1.PlaybackState',
      '10': 'state'
    },
    {'1': 'current_frame', '3': 3, '4': 1, '5': 4, '10': 'currentFrame'},
    {'1': 'generation_id', '3': 4, '4': 1, '5': 4, '10': 'generationId'},
    {'1': 'detail', '3': 5, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `PlaybackEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List playbackEventDescriptor = $convert.base64Decode(
    'Cg1QbGF5YmFja0V2ZW50Eh8KC3BsYXliYWNrX2lkGAEgASgJUgpwbGF5YmFja0lkEjgKBXN0YX'
    'RlGAIgASgOMiIubGlzdGVuZXIuY29udHJvbC52MS5QbGF5YmFja1N0YXRlUgVzdGF0ZRIjCg1j'
    'dXJyZW50X2ZyYW1lGAMgASgEUgxjdXJyZW50RnJhbWUSIwoNZ2VuZXJhdGlvbl9pZBgEIAEoBF'
    'IMZ2VuZXJhdGlvbklkEhYKBmRldGFpbBgFIAEoCVIGZGV0YWls');
