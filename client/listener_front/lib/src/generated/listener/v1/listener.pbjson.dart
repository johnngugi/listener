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

@$core.Deprecated('Use getArtworkRequestDescriptor instead')
const GetArtworkRequest$json = {
  '1': 'GetArtworkRequest',
  '2': [
    {'1': 'artwork_id', '3': 1, '4': 1, '5': 3, '10': 'artworkId'},
  ],
};

/// Descriptor for `GetArtworkRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getArtworkRequestDescriptor = $convert.base64Decode(
    'ChFHZXRBcnR3b3JrUmVxdWVzdBIdCgphcnR3b3JrX2lkGAEgASgDUglhcnR3b3JrSWQ=');

@$core.Deprecated('Use getArtworkResponseDescriptor instead')
const GetArtworkResponse$json = {
  '1': 'GetArtworkResponse',
  '2': [
    {'1': 'artwork_id', '3': 1, '4': 1, '5': 3, '10': 'artworkId'},
    {'1': 'mime_type', '3': 2, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'width', '3': 3, '4': 1, '5': 13, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 13, '10': 'height'},
    {'1': 'data', '3': 5, '4': 1, '5': 12, '10': 'data'},
  ],
};

/// Descriptor for `GetArtworkResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List getArtworkResponseDescriptor = $convert.base64Decode(
    'ChJHZXRBcnR3b3JrUmVzcG9uc2USHQoKYXJ0d29ya19pZBgBIAEoA1IJYXJ0d29ya0lkEhsKCW'
    '1pbWVfdHlwZRgCIAEoCVIIbWltZVR5cGUSFAoFd2lkdGgYAyABKA1SBXdpZHRoEhYKBmhlaWdo'
    'dBgEIAEoDVIGaGVpZ2h0EhIKBGRhdGEYBSABKAxSBGRhdGE=');

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
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'size_bytes', '3': 2, '4': 1, '5': 4, '10': 'sizeBytes'},
    {
      '1': 'modified_unix_nanos',
      '3': 3,
      '4': 1,
      '5': 3,
      '10': 'modifiedUnixNanos'
    },
    {'1': 'title', '3': 4, '4': 1, '5': 9, '9': 0, '10': 'title', '17': true},
    {
      '1': 'track_artist',
      '3': 5,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'trackArtist',
      '17': true
    },
    {
      '1': 'album_artist',
      '3': 6,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'albumArtist',
      '17': true
    },
    {'1': 'album', '3': 7, '4': 1, '5': 9, '9': 3, '10': 'album', '17': true},
    {
      '1': 'track_number',
      '3': 8,
      '4': 1,
      '5': 13,
      '9': 4,
      '10': 'trackNumber',
      '17': true
    },
    {
      '1': 'disc_number',
      '3': 9,
      '4': 1,
      '5': 13,
      '9': 5,
      '10': 'discNumber',
      '17': true
    },
    {
      '1': 'release_date',
      '3': 10,
      '4': 1,
      '5': 9,
      '9': 6,
      '10': 'releaseDate',
      '17': true
    },
    {
      '1': 'duration_ms',
      '3': 11,
      '4': 1,
      '5': 4,
      '9': 7,
      '10': 'durationMs',
      '17': true
    },
    {'1': 'codec', '3': 12, '4': 1, '5': 9, '10': 'codec'},
    {'1': 'sample_rate', '3': 13, '4': 1, '5': 13, '10': 'sampleRate'},
    {'1': 'bits_per_sample', '3': 14, '4': 1, '5': 13, '10': 'bitsPerSample'},
    {
      '1': 'date_added_unix_seconds',
      '3': 15,
      '4': 1,
      '5': 3,
      '10': 'dateAddedUnixSeconds'
    },
    {
      '1': 'artwork_id',
      '3': 16,
      '4': 1,
      '5': 3,
      '9': 8,
      '10': 'artworkId',
      '17': true
    },
  ],
  '8': [
    {'1': '_title'},
    {'1': '_track_artist'},
    {'1': '_album_artist'},
    {'1': '_album'},
    {'1': '_track_number'},
    {'1': '_disc_number'},
    {'1': '_release_date'},
    {'1': '_duration_ms'},
    {'1': '_artwork_id'},
  ],
};

/// Descriptor for `Track`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List trackDescriptor = $convert.base64Decode(
    'CgVUcmFjaxIOCgJpZBgBIAEoCVICaWQSHQoKc2l6ZV9ieXRlcxgCIAEoBFIJc2l6ZUJ5dGVzEi'
    '4KE21vZGlmaWVkX3VuaXhfbmFub3MYAyABKANSEW1vZGlmaWVkVW5peE5hbm9zEhkKBXRpdGxl'
    'GAQgASgJSABSBXRpdGxliAEBEiYKDHRyYWNrX2FydGlzdBgFIAEoCUgBUgt0cmFja0FydGlzdI'
    'gBARImCgxhbGJ1bV9hcnRpc3QYBiABKAlIAlILYWxidW1BcnRpc3SIAQESGQoFYWxidW0YByAB'
    'KAlIA1IFYWxidW2IAQESJgoMdHJhY2tfbnVtYmVyGAggASgNSARSC3RyYWNrTnVtYmVyiAEBEi'
    'QKC2Rpc2NfbnVtYmVyGAkgASgNSAVSCmRpc2NOdW1iZXKIAQESJgoMcmVsZWFzZV9kYXRlGAog'
    'ASgJSAZSC3JlbGVhc2VEYXRliAEBEiQKC2R1cmF0aW9uX21zGAsgASgESAdSCmR1cmF0aW9uTX'
    'OIAQESFAoFY29kZWMYDCABKAlSBWNvZGVjEh8KC3NhbXBsZV9yYXRlGA0gASgNUgpzYW1wbGVS'
    'YXRlEiYKD2JpdHNfcGVyX3NhbXBsZRgOIAEoDVINYml0c1BlclNhbXBsZRI1ChdkYXRlX2FkZG'
    'VkX3VuaXhfc2Vjb25kcxgPIAEoA1IUZGF0ZUFkZGVkVW5peFNlY29uZHMSIgoKYXJ0d29ya19p'
    'ZBgQIAEoA0gIUglhcnR3b3JrSWSIAQFCCAoGX3RpdGxlQg8KDV90cmFja19hcnRpc3RCDwoNX2'
    'FsYnVtX2FydGlzdEIICgZfYWxidW1CDwoNX3RyYWNrX251bWJlckIOCgxfZGlzY19udW1iZXJC'
    'DwoNX3JlbGVhc2VfZGF0ZUIOCgxfZHVyYXRpb25fbXNCDQoLX2FydHdvcmtfaWQ=');

@$core.Deprecated('Use startRequestDescriptor instead')
const StartRequest$json = {
  '1': 'StartRequest',
  '2': [
    {'1': 'track_id', '3': 1, '4': 1, '5': 9, '10': 'trackId'},
    {'1': 'start_frame', '3': 2, '4': 1, '5': 4, '10': 'startFrame'},
  ],
};

/// Descriptor for `StartRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startRequestDescriptor = $convert.base64Decode(
    'CgxTdGFydFJlcXVlc3QSGQoIdHJhY2tfaWQYASABKAlSB3RyYWNrSWQSHwoLc3RhcnRfZnJhbW'
    'UYAiABKARSCnN0YXJ0RnJhbWU=');

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
    {'1': 'track_id', '3': 3, '4': 1, '5': 9, '10': 'trackId'},
    {'1': 'current_frame', '3': 4, '4': 1, '5': 4, '10': 'currentFrame'},
    {'1': 'generation_id', '3': 5, '4': 1, '5': 4, '10': 'generationId'},
  ],
};

/// Descriptor for `StatusResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List statusResponseDescriptor = $convert.base64Decode(
    'Cg5TdGF0dXNSZXNwb25zZRIfCgtwbGF5YmFja19pZBgBIAEoCVIKcGxheWJhY2tJZBI4CgVzdG'
    'F0ZRgCIAEoDjIiLmxpc3RlbmVyLmNvbnRyb2wudjEuUGxheWJhY2tTdGF0ZVIFc3RhdGUSGQoI'
    'dHJhY2tfaWQYAyABKAlSB3RyYWNrSWQSIwoNY3VycmVudF9mcmFtZRgEIAEoBFIMY3VycmVudE'
    'ZyYW1lEiMKDWdlbmVyYXRpb25faWQYBSABKARSDGdlbmVyYXRpb25JZA==');

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
