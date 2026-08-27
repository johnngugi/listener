import 'package:equatable/equatable.dart';
import 'package:listener_front/src/models/track.dart';

enum LibraryStatus { initial, loadingFirstPage, ready, loadingMore, failure }

enum LibrarySortField {
  trackNumber,
  title,
  duration,
  albumArtist,
  album,
  releaseDate,
  dateAdded,
}

enum LibrarySortDirection { ascending, descending }

class LibraryState extends Equatable {
  const LibraryState({
    required this.tracks,
    required this.status,
    required this.nextPageToken,
    required this.totalSize,
    required this.sortField,
    required this.sortDirection,
    required this.isRefreshing,
    this.errorMessage,
  });

  factory LibraryState.initial() {
    return const LibraryState(
      tracks: [],
      status: LibraryStatus.initial,
      nextPageToken: '',
      totalSize: 0,
      sortField: LibrarySortField.albumArtist,
      sortDirection: LibrarySortDirection.ascending,
      isRefreshing: false,
    );
  }

  final List<Track> tracks;
  final LibraryStatus status;
  final String nextPageToken;
  final int totalSize;
  final LibrarySortField sortField;
  final LibrarySortDirection sortDirection;
  final bool isRefreshing;
  final String? errorMessage;

  LibraryState copyWith({
    List<Track>? tracks,
    LibraryStatus? status,
    String? nextPageToken,
    int? totalSize,
    LibrarySortField? sortField,
    LibrarySortDirection? sortDirection,
    bool? isRefreshing,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      status: status ?? this.status,
      nextPageToken: nextPageToken ?? this.nextPageToken,
      totalSize: totalSize ?? this.totalSize,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }

  bool get hasMore => nextPageToken.isNotEmpty;

  bool get isInitialLoading => status == LibraryStatus.loadingFirstPage;

  bool get isLoadingMore => status == LibraryStatus.loadingMore;

  @override
  List<Object?> get props => [
    tracks,
    status,
    nextPageToken,
    totalSize,
    sortField,
    sortDirection,
    isRefreshing,
    errorMessage,
  ];
}
