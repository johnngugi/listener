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

  Future<void> _loadPage({required bool isFirstPage}) async {
    emit(
      state.copyWith(
        status: isFirstPage
            ? LibraryStatus.loadingFirstPage
            : LibraryStatus.loadingMore,
        clearError: true,
      ),
    );

    try {
      final response = await _listTracks(
        grpc.ListTracksRequest(
          pageSize: libraryPageSize,
          pageToken: isFirstPage ? '' : state.nextPageToken,
        ),
      );

      if (isClosed) return;

      emit(
        state.copyWith(
          tracks: [
            if (!isFirstPage) ...state.tracks,
            ...mapTracks(response.tracks),
          ],
          nextPageToken: response.nextPageToken,
          totalSize: response.totalSize.toInt(),
          status: LibraryStatus.ready,
        ),
      );
    } catch (error) {
      if (isClosed) return;

      emit(
        state.copyWith(
          status: LibraryStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }
}

List<model_track.Track> mapTracks(pb.PbList<grpc.Track> tracks) {
  final store = List<model_track.Track>.empty(growable: true);

  for (final value in tracks) {
    final track = model_track.Track(
      id: value.id,
      number: value.hasTrackNumber()
          ? value.trackNumber.toString()
          : value.id.toString(),
      title: value.title,
      artist: value.albumArtist,
      album: value.album,
      releaseDate: formatReleaseDate(value.releaseDate),
      dateAdded: '15 May 2026',
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
