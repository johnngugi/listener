import 'package:equatable/equatable.dart';
import 'package:listener_front/src/models/track.dart';

enum LibraryStatus { initial, loadingFirstPage, ready, loadingMore, failure }

class LibraryState extends Equatable {
  const LibraryState({
    required this.tracks,
    required this.status,
    required this.nextPageToken,
    required this.totalSize,
    this.errorMessage,
  });

  factory LibraryState.initial() {
    return const LibraryState(
      tracks: [],
      status: LibraryStatus.initial,
      nextPageToken: '',
      totalSize: 0,
    );
  }

  final List<Track> tracks;
  final LibraryStatus status;
  final String nextPageToken;
  final int totalSize;
  final String? errorMessage;

  LibraryState copyWith({
    List<Track>? tracks,
    LibraryStatus? status,
    String? nextPageToken,
    int? totalSize,
    String? errorMessage,
    bool clearError = false,
  }) {
    return LibraryState(
      tracks: tracks ?? this.tracks,
      status: status ?? this.status,
      nextPageToken: nextPageToken ?? this.nextPageToken,
      totalSize: totalSize ?? this.totalSize,
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
    errorMessage,
  ];
}
