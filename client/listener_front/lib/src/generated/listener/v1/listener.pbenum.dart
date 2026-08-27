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

import 'package:protobuf/protobuf.dart' as $pb;

class TrackSortField extends $pb.ProtobufEnum {
  static const TrackSortField TRACK_SORT_FIELD_UNSPECIFIED =
      TrackSortField._(0, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_UNSPECIFIED');
  static const TrackSortField TRACK_SORT_FIELD_TRACK_NUMBER = TrackSortField._(
      1, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_TRACK_NUMBER');
  static const TrackSortField TRACK_SORT_FIELD_TITLE =
      TrackSortField._(2, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_TITLE');
  static const TrackSortField TRACK_SORT_FIELD_DURATION =
      TrackSortField._(3, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_DURATION');
  static const TrackSortField TRACK_SORT_FIELD_ALBUM_ARTIST = TrackSortField._(
      4, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_ALBUM_ARTIST');
  static const TrackSortField TRACK_SORT_FIELD_ALBUM =
      TrackSortField._(5, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_ALBUM');
  static const TrackSortField TRACK_SORT_FIELD_RELEASE_DATE = TrackSortField._(
      6, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_RELEASE_DATE');
  static const TrackSortField TRACK_SORT_FIELD_DATE_ADDED =
      TrackSortField._(7, _omitEnumNames ? '' : 'TRACK_SORT_FIELD_DATE_ADDED');

  static const $core.List<TrackSortField> values = <TrackSortField>[
    TRACK_SORT_FIELD_UNSPECIFIED,
    TRACK_SORT_FIELD_TRACK_NUMBER,
    TRACK_SORT_FIELD_TITLE,
    TRACK_SORT_FIELD_DURATION,
    TRACK_SORT_FIELD_ALBUM_ARTIST,
    TRACK_SORT_FIELD_ALBUM,
    TRACK_SORT_FIELD_RELEASE_DATE,
    TRACK_SORT_FIELD_DATE_ADDED,
  ];

  static final $core.List<TrackSortField?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static TrackSortField? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const TrackSortField._(super.value, super.name);
}

class SortDirection extends $pb.ProtobufEnum {
  static const SortDirection SORT_DIRECTION_UNSPECIFIED =
      SortDirection._(0, _omitEnumNames ? '' : 'SORT_DIRECTION_UNSPECIFIED');
  static const SortDirection SORT_DIRECTION_ASCENDING =
      SortDirection._(1, _omitEnumNames ? '' : 'SORT_DIRECTION_ASCENDING');
  static const SortDirection SORT_DIRECTION_DESCENDING =
      SortDirection._(2, _omitEnumNames ? '' : 'SORT_DIRECTION_DESCENDING');

  static const $core.List<SortDirection> values = <SortDirection>[
    SORT_DIRECTION_UNSPECIFIED,
    SORT_DIRECTION_ASCENDING,
    SORT_DIRECTION_DESCENDING,
  ];

  static final $core.List<SortDirection?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static SortDirection? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const SortDirection._(super.value, super.name);
}

class PlaybackState extends $pb.ProtobufEnum {
  static const PlaybackState PLAYBACK_STATE_UNSPECIFIED =
      PlaybackState._(0, _omitEnumNames ? '' : 'PLAYBACK_STATE_UNSPECIFIED');
  static const PlaybackState PLAYBACK_STATE_IDLE =
      PlaybackState._(1, _omitEnumNames ? '' : 'PLAYBACK_STATE_IDLE');
  static const PlaybackState PLAYBACK_STATE_STARTING =
      PlaybackState._(2, _omitEnumNames ? '' : 'PLAYBACK_STATE_STARTING');
  static const PlaybackState PLAYBACK_STATE_PLAYING =
      PlaybackState._(3, _omitEnumNames ? '' : 'PLAYBACK_STATE_PLAYING');
  static const PlaybackState PLAYBACK_STATE_PAUSED =
      PlaybackState._(4, _omitEnumNames ? '' : 'PLAYBACK_STATE_PAUSED');
  static const PlaybackState PLAYBACK_STATE_STOPPED =
      PlaybackState._(5, _omitEnumNames ? '' : 'PLAYBACK_STATE_STOPPED');
  static const PlaybackState PLAYBACK_STATE_ENDED =
      PlaybackState._(6, _omitEnumNames ? '' : 'PLAYBACK_STATE_ENDED');
  static const PlaybackState PLAYBACK_STATE_ERROR =
      PlaybackState._(7, _omitEnumNames ? '' : 'PLAYBACK_STATE_ERROR');

  static const $core.List<PlaybackState> values = <PlaybackState>[
    PLAYBACK_STATE_UNSPECIFIED,
    PLAYBACK_STATE_IDLE,
    PLAYBACK_STATE_STARTING,
    PLAYBACK_STATE_PLAYING,
    PLAYBACK_STATE_PAUSED,
    PLAYBACK_STATE_STOPPED,
    PLAYBACK_STATE_ENDED,
    PLAYBACK_STATE_ERROR,
  ];

  static final $core.List<PlaybackState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 7);
  static PlaybackState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PlaybackState._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
