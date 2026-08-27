import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/models/library_state.dart';
import 'package:listener_front/src/models/track.dart' as model_track;
import 'package:protobuf/protobuf.dart' as pb;

typedef ListTracksCall =
    Future<grpc.ListTracksResponse> Function(grpc.ListTracksRequest request);

class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit(this._listTracks) : super(LibraryState.initial());

  factory LibraryCubit.connect(grpc.ListenerLibraryClient libraryClient) {
    return LibraryCubit(libraryClient.listTracks);
  }

  final ListTracksCall _listTracks;
  int _requestGeneration = 0;

  static const libraryPageSize = 200;

  Future<void> listTracks() async {
    if (state.status != LibraryStatus.initial &&
        !(state.status == LibraryStatus.failure && state.tracks.isEmpty)) {
      return;
    }

    await _loadPage(isFirstPage: true);
  }

  Future<void> loadNextPage() async {
    if (state.status != LibraryStatus.ready || !state.hasMore) return;

    await _loadPage(isFirstPage: false);
  }

  Future<void> retry() async {
    if (state.status != LibraryStatus.failure) return;

    await _loadPage(isFirstPage: state.tracks.isEmpty);
  }

  Future<void> setSort(LibrarySortField field) async {
    final direction = state.sortField == field
        ? switch (state.sortDirection) {
            LibrarySortDirection.ascending => LibrarySortDirection.descending,
            LibrarySortDirection.descending => LibrarySortDirection.ascending,
          }
        : LibrarySortDirection.ascending;
    final hasTracks = state.tracks.isNotEmpty;

    _requestGeneration++;
    emit(
      state.copyWith(
        status: hasTracks
            ? LibraryStatus.ready
            : LibraryStatus.loadingFirstPage,
        nextPageToken: '',
        sortField: field,
        sortDirection: direction,
        isRefreshing: hasTracks,
        clearError: true,
      ),
    );

    await _loadPage(isFirstPage: true, backgroundRefresh: hasTracks);
  }

  Future<void> _loadPage({
    required bool isFirstPage,
    bool backgroundRefresh = false,
  }) async {
    final generation = _requestGeneration;
    final previousTracks = state.tracks;
    final pageToken = isFirstPage ? '' : state.nextPageToken;
    final sortField = state.sortField;
    final sortDirection = state.sortDirection;

    if (!backgroundRefresh) {
      emit(
        state.copyWith(
          status: isFirstPage
              ? LibraryStatus.loadingFirstPage
              : LibraryStatus.loadingMore,
          isRefreshing: false,
          clearError: true,
        ),
      );
    }

    try {
      final response = await _listTracks(
        grpc.ListTracksRequest(
          pageSize: libraryPageSize,
          pageToken: pageToken,
          sortField: _grpcSortField(sortField),
          sortDirection: _grpcSortDirection(sortDirection),
        ),
      );

      if (isClosed || generation != _requestGeneration) return;

      emit(
        state.copyWith(
          tracks: [
            if (!isFirstPage) ...previousTracks,
            ...mapTracks(response.tracks),
          ],
          nextPageToken: response.nextPageToken,
          totalSize: response.totalSize.toInt(),
          status: LibraryStatus.ready,
          isRefreshing: false,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _requestGeneration) return;

      if (backgroundRefresh && previousTracks.isNotEmpty) {
        emit(
          state.copyWith(
            status: LibraryStatus.ready,
            isRefreshing: false,
            errorMessage: error.toString(),
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          status: LibraryStatus.failure,
          isRefreshing: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }
}

grpc.TrackSortField _grpcSortField(LibrarySortField field) {
  return switch (field) {
    LibrarySortField.trackNumber =>
      grpc.TrackSortField.TRACK_SORT_FIELD_TRACK_NUMBER,
    LibrarySortField.title => grpc.TrackSortField.TRACK_SORT_FIELD_TITLE,
    LibrarySortField.duration => grpc.TrackSortField.TRACK_SORT_FIELD_DURATION,
    LibrarySortField.albumArtist =>
      grpc.TrackSortField.TRACK_SORT_FIELD_ALBUM_ARTIST,
    LibrarySortField.album => grpc.TrackSortField.TRACK_SORT_FIELD_ALBUM,
    LibrarySortField.releaseDate =>
      grpc.TrackSortField.TRACK_SORT_FIELD_RELEASE_DATE,
    LibrarySortField.dateAdded =>
      grpc.TrackSortField.TRACK_SORT_FIELD_DATE_ADDED,
  };
}

grpc.SortDirection _grpcSortDirection(LibrarySortDirection direction) {
  return switch (direction) {
    LibrarySortDirection.ascending =>
      grpc.SortDirection.SORT_DIRECTION_ASCENDING,
    LibrarySortDirection.descending =>
      grpc.SortDirection.SORT_DIRECTION_DESCENDING,
  };
}

List<model_track.Track> mapTracks(pb.PbList<grpc.Track> tracks) {
  final store = List<model_track.Track>.empty(growable: true);

  for (final value in tracks) {
    final track = model_track.Track(
      id: value.id,
      number: value.hasTrackNumber() ? value.trackNumber.toString() : '—',
      title: value.title,
      artist: value.trackArtist.isNotEmpty
          ? value.trackArtist
          : value.albumArtist,
      album: value.album,
      releaseDate: formatReleaseDate(value.releaseDate),
      dateAdded: formatUnixSeconds(value.dateAddedUnixSeconds.toInt()),
      plays: '0',
      artworkId: value.hasArtworkId() ? value.artworkId.toInt() : null,
      durationMilliseconds: value.durationMs.toInt(),
      sampleRate: value.sampleRate,
    );

    store.add(track);
  }

  return store;
}

String formatReleaseDate(String releaseDate) {
  final date = DateTime.tryParse(releaseDate);

  if (date != null) {
    return DateFormat('d MMM yyyy').format(date);
  }

  final year = int.tryParse(releaseDate);
  if (year != null) {
    return year.toString();
  }

  return "";
}

String formatUnixSeconds(int unixSeconds) {
  if (unixSeconds <= 0) return '';
  final date = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * Duration.millisecondsPerSecond,
    isUtc: true,
  ).toLocal();
  return DateFormat('d MMM yyyy').format(date);
}
