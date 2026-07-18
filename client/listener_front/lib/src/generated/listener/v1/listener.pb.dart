// This is a generated file - do not edit.
//
// Generated from listener/v1/listener.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'listener.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'listener.pbenum.dart';

class ListTracksRequest extends $pb.GeneratedMessage {
  factory ListTracksRequest({
    $core.int? pageSize,
    $core.String? pageToken,
  }) {
    final result = create();
    if (pageSize != null) result.pageSize = pageSize;
    if (pageToken != null) result.pageToken = pageToken;
    return result;
  }

  ListTracksRequest._();

  factory ListTracksRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTracksRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTracksRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'pageSize', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'pageToken')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTracksRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTracksRequest copyWith(void Function(ListTracksRequest) updates) =>
      super.copyWith((message) => updates(message as ListTracksRequest))
          as ListTracksRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTracksRequest create() => ListTracksRequest._();
  @$core.override
  ListTracksRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTracksRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTracksRequest>(create);
  static ListTracksRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get pageSize => $_getIZ(0);
  @$pb.TagNumber(1)
  set pageSize($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPageSize() => $_has(0);
  @$pb.TagNumber(1)
  void clearPageSize() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get pageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set pageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearPageToken() => $_clearField(2);
}

class ListTracksResponse extends $pb.GeneratedMessage {
  factory ListTracksResponse({
    $core.Iterable<Track>? tracks,
    $core.String? nextPageToken,
    $fixnum.Int64? totalSize,
  }) {
    final result = create();
    if (tracks != null) result.tracks.addAll(tracks);
    if (nextPageToken != null) result.nextPageToken = nextPageToken;
    if (totalSize != null) result.totalSize = totalSize;
    return result;
  }

  ListTracksResponse._();

  factory ListTracksResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ListTracksResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ListTracksResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..pPM<Track>(1, _omitFieldNames ? '' : 'tracks', subBuilder: Track.create)
    ..aOS(2, _omitFieldNames ? '' : 'nextPageToken')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'totalSize', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTracksResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ListTracksResponse copyWith(void Function(ListTracksResponse) updates) =>
      super.copyWith((message) => updates(message as ListTracksResponse))
          as ListTracksResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ListTracksResponse create() => ListTracksResponse._();
  @$core.override
  ListTracksResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ListTracksResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ListTracksResponse>(create);
  static ListTracksResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<Track> get tracks => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get nextPageToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set nextPageToken($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNextPageToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearNextPageToken() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get totalSize => $_getI64(2);
  @$pb.TagNumber(3)
  set totalSize($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTotalSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearTotalSize() => $_clearField(3);
}

class Track extends $pb.GeneratedMessage {
  factory Track({
    $fixnum.Int64? id,
    $core.String? path,
    $fixnum.Int64? sizeBytes,
    $fixnum.Int64? modifiedUnixNanos,
    $core.String? title,
    $core.String? trackArtist,
    $core.String? albumArtist,
    $core.String? album,
    $core.int? trackNumber,
    $core.int? discNumber,
    $core.String? releaseDate,
    $fixnum.Int64? durationMs,
    $core.String? codec,
    $core.int? sampleRate,
    $core.int? bitsPerSample,
    $fixnum.Int64? dateAddedUnixSeconds,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (path != null) result.path = path;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (modifiedUnixNanos != null) result.modifiedUnixNanos = modifiedUnixNanos;
    if (title != null) result.title = title;
    if (trackArtist != null) result.trackArtist = trackArtist;
    if (albumArtist != null) result.albumArtist = albumArtist;
    if (album != null) result.album = album;
    if (trackNumber != null) result.trackNumber = trackNumber;
    if (discNumber != null) result.discNumber = discNumber;
    if (releaseDate != null) result.releaseDate = releaseDate;
    if (durationMs != null) result.durationMs = durationMs;
    if (codec != null) result.codec = codec;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (bitsPerSample != null) result.bitsPerSample = bitsPerSample;
    if (dateAddedUnixSeconds != null)
      result.dateAddedUnixSeconds = dateAddedUnixSeconds;
    return result;
  }

  Track._();

  factory Track.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Track.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Track',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'path')
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'sizeBytes', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(4, _omitFieldNames ? '' : 'modifiedUnixNanos')
    ..aOS(5, _omitFieldNames ? '' : 'title')
    ..aOS(6, _omitFieldNames ? '' : 'trackArtist')
    ..aOS(7, _omitFieldNames ? '' : 'albumArtist')
    ..aOS(8, _omitFieldNames ? '' : 'album')
    ..aI(9, _omitFieldNames ? '' : 'trackNumber',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(10, _omitFieldNames ? '' : 'discNumber',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(11, _omitFieldNames ? '' : 'releaseDate')
    ..a<$fixnum.Int64>(
        12, _omitFieldNames ? '' : 'durationMs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(13, _omitFieldNames ? '' : 'codec')
    ..aI(14, _omitFieldNames ? '' : 'sampleRate',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(15, _omitFieldNames ? '' : 'bitsPerSample',
        fieldType: $pb.PbFieldType.OU3)
    ..aInt64(16, _omitFieldNames ? '' : 'dateAddedUnixSeconds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Track clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Track copyWith(void Function(Track) updates) =>
      super.copyWith((message) => updates(message as Track)) as Track;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Track create() => Track._();
  @$core.override
  Track createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Track getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Track>(create);
  static Track? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get path => $_getSZ(1);
  @$pb.TagNumber(2)
  set path($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPath() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get sizeBytes => $_getI64(2);
  @$pb.TagNumber(3)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSizeBytes() => $_has(2);
  @$pb.TagNumber(3)
  void clearSizeBytes() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get modifiedUnixNanos => $_getI64(3);
  @$pb.TagNumber(4)
  set modifiedUnixNanos($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModifiedUnixNanos() => $_has(3);
  @$pb.TagNumber(4)
  void clearModifiedUnixNanos() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get title => $_getSZ(4);
  @$pb.TagNumber(5)
  set title($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTitle() => $_has(4);
  @$pb.TagNumber(5)
  void clearTitle() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get trackArtist => $_getSZ(5);
  @$pb.TagNumber(6)
  set trackArtist($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTrackArtist() => $_has(5);
  @$pb.TagNumber(6)
  void clearTrackArtist() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get albumArtist => $_getSZ(6);
  @$pb.TagNumber(7)
  set albumArtist($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasAlbumArtist() => $_has(6);
  @$pb.TagNumber(7)
  void clearAlbumArtist() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get album => $_getSZ(7);
  @$pb.TagNumber(8)
  set album($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAlbum() => $_has(7);
  @$pb.TagNumber(8)
  void clearAlbum() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get trackNumber => $_getIZ(8);
  @$pb.TagNumber(9)
  set trackNumber($core.int value) => $_setUnsignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTrackNumber() => $_has(8);
  @$pb.TagNumber(9)
  void clearTrackNumber() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get discNumber => $_getIZ(9);
  @$pb.TagNumber(10)
  set discNumber($core.int value) => $_setUnsignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasDiscNumber() => $_has(9);
  @$pb.TagNumber(10)
  void clearDiscNumber() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get releaseDate => $_getSZ(10);
  @$pb.TagNumber(11)
  set releaseDate($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasReleaseDate() => $_has(10);
  @$pb.TagNumber(11)
  void clearReleaseDate() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get durationMs => $_getI64(11);
  @$pb.TagNumber(12)
  set durationMs($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasDurationMs() => $_has(11);
  @$pb.TagNumber(12)
  void clearDurationMs() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get codec => $_getSZ(12);
  @$pb.TagNumber(13)
  set codec($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasCodec() => $_has(12);
  @$pb.TagNumber(13)
  void clearCodec() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get sampleRate => $_getIZ(13);
  @$pb.TagNumber(14)
  set sampleRate($core.int value) => $_setUnsignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasSampleRate() => $_has(13);
  @$pb.TagNumber(14)
  void clearSampleRate() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get bitsPerSample => $_getIZ(14);
  @$pb.TagNumber(15)
  set bitsPerSample($core.int value) => $_setUnsignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasBitsPerSample() => $_has(14);
  @$pb.TagNumber(15)
  void clearBitsPerSample() => $_clearField(15);

  @$pb.TagNumber(16)
  $fixnum.Int64 get dateAddedUnixSeconds => $_getI64(15);
  @$pb.TagNumber(16)
  set dateAddedUnixSeconds($fixnum.Int64 value) => $_setInt64(15, value);
  @$pb.TagNumber(16)
  $core.bool hasDateAddedUnixSeconds() => $_has(15);
  @$pb.TagNumber(16)
  void clearDateAddedUnixSeconds() => $_clearField(16);
}

class StartRequest extends $pb.GeneratedMessage {
  factory StartRequest({
    $core.String? mediaPath,
    $fixnum.Int64? startFrame,
  }) {
    final result = create();
    if (mediaPath != null) result.mediaPath = mediaPath;
    if (startFrame != null) result.startFrame = startFrame;
    return result;
  }

  StartRequest._();

  factory StartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mediaPath')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'startFrame', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartRequest copyWith(void Function(StartRequest) updates) =>
      super.copyWith((message) => updates(message as StartRequest))
          as StartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartRequest create() => StartRequest._();
  @$core.override
  StartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartRequest>(create);
  static StartRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mediaPath => $_getSZ(0);
  @$pb.TagNumber(1)
  set mediaPath($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMediaPath() => $_has(0);
  @$pb.TagNumber(1)
  void clearMediaPath() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get startFrame => $_getI64(1);
  @$pb.TagNumber(2)
  set startFrame($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStartFrame() => $_has(1);
  @$pb.TagNumber(2)
  void clearStartFrame() => $_clearField(2);
}

class StartResponse extends $pb.GeneratedMessage {
  factory StartResponse({
    $core.String? playbackId,
    PlaybackState? state,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    if (state != null) result.state = state;
    return result;
  }

  StartResponse._();

  factory StartResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..aE<PlaybackState>(2, _omitFieldNames ? '' : 'state',
        enumValues: PlaybackState.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartResponse copyWith(void Function(StartResponse) updates) =>
      super.copyWith((message) => updates(message as StartResponse))
          as StartResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartResponse create() => StartResponse._();
  @$core.override
  StartResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartResponse>(create);
  static StartResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);

  @$pb.TagNumber(2)
  PlaybackState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(PlaybackState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);
}

class StopRequest extends $pb.GeneratedMessage {
  factory StopRequest({
    $core.String? playbackId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    return result;
  }

  StopRequest._();

  factory StopRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StopRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StopRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StopRequest copyWith(void Function(StopRequest) updates) =>
      super.copyWith((message) => updates(message as StopRequest))
          as StopRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StopRequest create() => StopRequest._();
  @$core.override
  StopRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StopRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StopRequest>(create);
  static StopRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);
}

class PauseRequest extends $pb.GeneratedMessage {
  factory PauseRequest({
    $core.String? playbackId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    return result;
  }

  PauseRequest._();

  factory PauseRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PauseRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PauseRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PauseRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PauseRequest copyWith(void Function(PauseRequest) updates) =>
      super.copyWith((message) => updates(message as PauseRequest))
          as PauseRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PauseRequest create() => PauseRequest._();
  @$core.override
  PauseRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PauseRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PauseRequest>(create);
  static PauseRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);
}

class ResumeRequest extends $pb.GeneratedMessage {
  factory ResumeRequest({
    $core.String? playbackId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    return result;
  }

  ResumeRequest._();

  factory ResumeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ResumeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ResumeRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResumeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ResumeRequest copyWith(void Function(ResumeRequest) updates) =>
      super.copyWith((message) => updates(message as ResumeRequest))
          as ResumeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ResumeRequest create() => ResumeRequest._();
  @$core.override
  ResumeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ResumeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ResumeRequest>(create);
  static ResumeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);
}

class SeekRequest extends $pb.GeneratedMessage {
  factory SeekRequest({
    $core.String? playbackId,
    $fixnum.Int64? frame,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    if (frame != null) result.frame = frame;
    return result;
  }

  SeekRequest._();

  factory SeekRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SeekRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SeekRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..a<$fixnum.Int64>(2, _omitFieldNames ? '' : 'frame', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SeekRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SeekRequest copyWith(void Function(SeekRequest) updates) =>
      super.copyWith((message) => updates(message as SeekRequest))
          as SeekRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SeekRequest create() => SeekRequest._();
  @$core.override
  SeekRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SeekRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SeekRequest>(create);
  static SeekRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get frame => $_getI64(1);
  @$pb.TagNumber(2)
  set frame($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFrame() => $_has(1);
  @$pb.TagNumber(2)
  void clearFrame() => $_clearField(2);
}

class StatusRequest extends $pb.GeneratedMessage {
  factory StatusRequest({
    $core.String? playbackId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    return result;
  }

  StatusRequest._();

  factory StatusRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatusRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatusRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusRequest copyWith(void Function(StatusRequest) updates) =>
      super.copyWith((message) => updates(message as StatusRequest))
          as StatusRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusRequest create() => StatusRequest._();
  @$core.override
  StatusRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatusRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatusRequest>(create);
  static StatusRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);
}

class WatchRequest extends $pb.GeneratedMessage {
  factory WatchRequest({
    $core.String? playbackId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    return result;
  }

  WatchRequest._();

  factory WatchRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory WatchRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'WatchRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  WatchRequest copyWith(void Function(WatchRequest) updates) =>
      super.copyWith((message) => updates(message as WatchRequest))
          as WatchRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WatchRequest create() => WatchRequest._();
  @$core.override
  WatchRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static WatchRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<WatchRequest>(create);
  static WatchRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);
}

class CommandResponse extends $pb.GeneratedMessage {
  factory CommandResponse({
    $core.String? playbackId,
    PlaybackState? state,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    if (state != null) result.state = state;
    return result;
  }

  CommandResponse._();

  factory CommandResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommandResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..aE<PlaybackState>(2, _omitFieldNames ? '' : 'state',
        enumValues: PlaybackState.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandResponse copyWith(void Function(CommandResponse) updates) =>
      super.copyWith((message) => updates(message as CommandResponse))
          as CommandResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommandResponse create() => CommandResponse._();
  @$core.override
  CommandResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommandResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommandResponse>(create);
  static CommandResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);

  @$pb.TagNumber(2)
  PlaybackState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(PlaybackState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);
}

class StatusResponse extends $pb.GeneratedMessage {
  factory StatusResponse({
    $core.String? playbackId,
    PlaybackState? state,
    $core.String? mediaPath,
    $fixnum.Int64? currentFrame,
    $fixnum.Int64? generationId,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    if (state != null) result.state = state;
    if (mediaPath != null) result.mediaPath = mediaPath;
    if (currentFrame != null) result.currentFrame = currentFrame;
    if (generationId != null) result.generationId = generationId;
    return result;
  }

  StatusResponse._();

  factory StatusResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StatusResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StatusResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..aE<PlaybackState>(2, _omitFieldNames ? '' : 'state',
        enumValues: PlaybackState.values)
    ..aOS(3, _omitFieldNames ? '' : 'mediaPath')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'currentFrame', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'generationId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StatusResponse copyWith(void Function(StatusResponse) updates) =>
      super.copyWith((message) => updates(message as StatusResponse))
          as StatusResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StatusResponse create() => StatusResponse._();
  @$core.override
  StatusResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StatusResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StatusResponse>(create);
  static StatusResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);

  @$pb.TagNumber(2)
  PlaybackState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(PlaybackState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get mediaPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set mediaPath($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMediaPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearMediaPath() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get currentFrame => $_getI64(3);
  @$pb.TagNumber(4)
  set currentFrame($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCurrentFrame() => $_has(3);
  @$pb.TagNumber(4)
  void clearCurrentFrame() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get generationId => $_getI64(4);
  @$pb.TagNumber(5)
  set generationId($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasGenerationId() => $_has(4);
  @$pb.TagNumber(5)
  void clearGenerationId() => $_clearField(5);
}

class PlaybackEvent extends $pb.GeneratedMessage {
  factory PlaybackEvent({
    $core.String? playbackId,
    PlaybackState? state,
    $fixnum.Int64? currentFrame,
    $fixnum.Int64? generationId,
    $core.String? detail,
  }) {
    final result = create();
    if (playbackId != null) result.playbackId = playbackId;
    if (state != null) result.state = state;
    if (currentFrame != null) result.currentFrame = currentFrame;
    if (generationId != null) result.generationId = generationId;
    if (detail != null) result.detail = detail;
    return result;
  }

  PlaybackEvent._();

  factory PlaybackEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PlaybackEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PlaybackEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'listener.control.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'playbackId')
    ..aE<PlaybackState>(2, _omitFieldNames ? '' : 'state',
        enumValues: PlaybackState.values)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'currentFrame', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'generationId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(5, _omitFieldNames ? '' : 'detail')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PlaybackEvent copyWith(void Function(PlaybackEvent) updates) =>
      super.copyWith((message) => updates(message as PlaybackEvent))
          as PlaybackEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PlaybackEvent create() => PlaybackEvent._();
  @$core.override
  PlaybackEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PlaybackEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PlaybackEvent>(create);
  static PlaybackEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get playbackId => $_getSZ(0);
  @$pb.TagNumber(1)
  set playbackId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPlaybackId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlaybackId() => $_clearField(1);

  @$pb.TagNumber(2)
  PlaybackState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(PlaybackState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get currentFrame => $_getI64(2);
  @$pb.TagNumber(3)
  set currentFrame($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrentFrame() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrentFrame() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get generationId => $_getI64(3);
  @$pb.TagNumber(4)
  set generationId($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasGenerationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearGenerationId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get detail => $_getSZ(4);
  @$pb.TagNumber(5)
  set detail($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDetail() => $_has(4);
  @$pb.TagNumber(5)
  void clearDetail() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
