import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/library_state.dart';
import 'package:listener_front/src/models/playback_state.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/theme.dart';
import 'package:listener_front/src/view_models/library_cubit.dart';
import 'package:listener_front/src/view_models/playback_cubit.dart';
import 'package:listener_front/src/widgets/artwork_image.dart';

// Shared column geometry so the header and every row line up exactly.
const _hPad = 32.0;
const _numW = 52.0;
const _favW = 52.0;
const _lengthW = 104.0;
const _releaseW = 128.0;
const _dateW = 128.0;
const _trackFlex = 34;
const _artistFlex = 17;
const _albumFlex = 19;
const _headerHeight = 56.0;
const _rowHeight = 80.0;

enum _LibraryLayout { minimal, compact, medium, full }

_LibraryLayout _libraryLayoutFor(double width) {
  if (width >= 1320) return _LibraryLayout.full;
  if (width >= 1050) return _LibraryLayout.medium;
  if (width >= 620) return _LibraryLayout.compact;
  return _LibraryLayout.minimal;
}

class TrackLibrary extends StatefulWidget {
  const TrackLibrary({super.key, this.showSidebarButton = false});

  final bool showSidebarButton;

  @override
  State<TrackLibrary> createState() => _TrackLibraryState();
}

class _TrackLibraryState extends State<TrackLibrary> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final horizontalPadding = compact ? 16.0 : _hPad;

        return Container(
          color: backgroundColor,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LibraryTopBar(showSidebarButton: widget.showSidebarButton),
              SizedBox(height: compact ? 18 : 24),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: const LibraryTitle(),
              ),
              SizedBox(height: compact ? 16 : 20),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: LibraryToolbar(
                  controller: _searchController,
                  query: _query,
                  onQueryChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 12),
              const TrackTableHeader(),
              Expanded(child: LibraryListPane(query: _query)),
            ],
          ),
        );
      },
    );
  }
}

class LibraryListPane extends StatelessWidget {
  const LibraryListPane({super.key, this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<LibraryCubit, LibraryState, bool>(
      selector: (state) => state.isRefreshing,
      builder: (context, isRefreshing) {
        return Stack(
          children: [
            LibraryList(query: query),
            if (isRefreshing)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: accentColor,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        );
      },
    );
  }
}

class LibraryList extends StatefulWidget {
  const LibraryList({super.key, this.query = ''});

  final String query;

  @override
  State<LibraryList> createState() => _LibraryListState();
}

class _LibraryListState extends State<LibraryList> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    context.read<LibraryCubit>().listTracks();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LibraryCubit, LibraryState>(
      builder: (BuildContext context, LibraryState state) {
        switch (state.status) {
          case LibraryStatus.initial:
            return const Center(child: CircularProgressIndicator());

          case LibraryStatus.loadingFirstPage:
            return const Center(child: CircularProgressIndicator());

          case LibraryStatus.loadingMore:
          case LibraryStatus.failure:
          case LibraryStatus.ready:
            if (state.tracks.isEmpty) {
              if (state.status == LibraryStatus.failure) {
                return _LibraryError(
                  message: state.errorMessage,
                  onRetry: context.read<LibraryCubit>().retry,
                );
              }

              return const Center(child: Text("Library empty"));
            } else {
              final normalizedQuery = widget.query.trim().toLowerCase();
              final visibleTracks = normalizedQuery.isEmpty
                  ? state.tracks
                  : state.tracks
                        .where(
                          (track) =>
                              [track.title, track.artist, track.album].any(
                                (value) => value.toLowerCase().contains(
                                  normalizedQuery,
                                ),
                              ),
                        )
                        .toList(growable: false);
              final showFooter =
                  normalizedQuery.isEmpty &&
                  (state.status == LibraryStatus.loadingMore ||
                      state.status == LibraryStatus.failure);

              if (visibleTracks.isEmpty && normalizedQuery.isNotEmpty) {
                return _NoSearchResults(query: widget.query);
              }

              return BlocSelector<
                PlaybackCubit,
                PlaybackState,
                ({String? trackId, PlaybackStatus status})
              >(
                selector: (playback) => (
                  trackId: playback.queue?.currentTrack.id,
                  status: playback.status,
                ),
                builder: (context, playback) => ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: visibleTracks.length + (showFooter ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == visibleTracks.length) {
                      if (state.status == LibraryStatus.loadingMore) {
                        return const _LoadingMoreIndicator();
                      }

                      return _LoadMoreError(
                        onRetry: context.read<LibraryCubit>().retry,
                      );
                    }

                    final track = visibleTracks[index];
                    return TrackRow(
                      track: track,
                      isCurrent: playback.trackId == track.id,
                      isPlaying:
                          playback.trackId == track.id &&
                          playback.status == PlaybackStatus.playing,
                    );
                  },
                ),
              );
            }
        }
      },
    );
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 400) {
      context.read<LibraryCubit>().loadNextPage();
    }
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, color: mutedColor, size: 34),
          const SizedBox(height: 10),
          const Text(
            'No matching tracks',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Nothing in the loaded library matches “$query”.',
            style: const TextStyle(color: mutedColor),
          ),
        ],
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: _rowHeight,
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _LibraryError extends StatelessWidget {
  const _LibraryError({required this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Could not load your library',
            style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: mutedColor),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Center(
        child: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Could not load more — retry'),
        ),
      ),
    );
  }
}

class LibraryTopBar extends StatelessWidget {
  const LibraryTopBar({super.key, this.showSidebarButton = false});

  final bool showSidebarButton;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 16 : _hPad,
            22,
            compact ? 16 : _hPad,
            0,
          ),
          child: Row(
            children: [
              if (showSidebarButton)
                IconButton(
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu, color: mutedColor, size: 28),
                ),
              const Spacer(),
              // TODO: Add profile access after the initial release.
            ],
          ),
        );
      },
    );
  }
}

class LibraryTitle extends StatelessWidget {
  const LibraryTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 14,
      runSpacing: 8,
      children: [_LibraryHeading(), _LibraryTrackCount()],
    );
  }
}

class _LibraryHeading extends StatelessWidget {
  const _LibraryHeading();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'My Tracks',
      style: TextStyle(
        color: textColor,
        fontFamily: 'Georgia',
        fontSize: 38,
        height: 1,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _LibraryTrackCount extends StatelessWidget {
  const _LibraryTrackCount();

  @override
  Widget build(BuildContext context) {
    return BlocSelector<LibraryCubit, LibraryState, int>(
      selector: (state) => state.totalSize,
      builder: (context, totalSize) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          '$totalSize ${totalSize == 1 ? 'track' : 'tracks'}',
          style: const TextStyle(
            color: mutedColor,
            fontSize: 17,
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class LibraryToolbar extends StatelessWidget {
  const LibraryToolbar({
    super.key,
    required this.controller,
    required this.query,
    required this.onQueryChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;

        final search = TextField(
          key: const Key('library-search-field'),
          controller: controller,
          onChanged: onQueryChanged,
          style: const TextStyle(color: textColor, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search tracks, artists, and albums',
            hintStyle: const TextStyle(color: mutedColor),
            prefixIcon: const Icon(Icons.search_rounded, color: mutedColor),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onQueryChanged('');
                    },
                    icon: const Icon(Icons.close_rounded, color: mutedColor),
                  ),
            filled: true,
            fillColor: panelColor,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: lineColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: accentColor),
            ),
          ),
        );

        final sortButton =
            BlocSelector<
              LibraryCubit,
              LibraryState,
              ({LibrarySortField field, LibrarySortDirection direction})
            >(
              selector: (state) =>
                  (field: state.sortField, direction: state.sortDirection),
              builder: (context, sort) => PopupMenuButton<LibrarySortField>(
                tooltip: 'Sort tracks',
                onSelected: context.read<LibraryCubit>().setSort,
                color: panelColor,
                itemBuilder: (context) => LibrarySortField.values
                    .map(
                      (field) => PopupMenuItem(
                        value: field,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: field == sort.field
                                  ? Icon(
                                      sort.direction ==
                                              LibrarySortDirection.ascending
                                          ? Icons.arrow_upward_rounded
                                          : Icons.arrow_downward_rounded,
                                      color: accentColor,
                                      size: 18,
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(_sortFieldLabel(field)),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                child: Container(
                  height: 46,
                  padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
                  decoration: BoxDecoration(
                    color: panelColor,
                    border: Border.all(color: lineColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.sort_rounded,
                        color: mutedColor,
                        size: 21,
                      ),
                      if (!compact) ...[
                        const SizedBox(width: 8),
                        Text(
                          _sortFieldLabel(sort.field),
                          style: const TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: mutedColor,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            );

        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            sortButton,
          ],
        );
      },
    );
  }
}

String _sortFieldLabel(LibrarySortField field) => switch (field) {
  LibrarySortField.trackNumber => 'Track number',
  LibrarySortField.title => 'Title',
  LibrarySortField.duration => 'Length',
  LibrarySortField.albumArtist => 'Artist',
  LibrarySortField.album => 'Album',
  LibrarySortField.releaseDate => 'Release date',
  LibrarySortField.dateAdded => 'Date added',
};

class TrackTableHeader extends StatelessWidget {
  const TrackTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _libraryLayoutFor(constraints.maxWidth);
        if (layout == _LibraryLayout.compact ||
            layout == _LibraryLayout.minimal) {
          return const SizedBox.shrink();
        }
        final horizontalPadding = layout == _LibraryLayout.full ? _hPad : 16.0;
        final showNumber = layout != _LibraryLayout.minimal;
        final showLength = layout != _LibraryLayout.minimal;
        final showDetails =
            layout == _LibraryLayout.medium || layout == _LibraryLayout.full;
        final showEverything = layout == _LibraryLayout.full;

        return Container(
          height: _headerHeight,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: lineColor)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              children: [
                if (showNumber) ...[
                  const SizedBox(
                    width: _numW,
                    child: SortableHeader(
                      '#',
                      LibrarySortField.trackNumber,
                      alignRight: true,
                    ),
                  ),
                  const VerticalRule(height: _headerHeight),
                ],
                const Expanded(
                  flex: _trackFlex,
                  child: SortableHeader('Track', LibrarySortField.title),
                ),
                if (showDetails) ...[
                  const SizedBox(
                    width: _favW,
                    child: HeaderIcon(Icons.favorite_border_rounded),
                  ),
                  const VerticalRule(height: _headerHeight),
                ],
                if (showLength) ...[
                  const SizedBox(
                    width: _lengthW,
                    child: SortableHeader('Length', LibrarySortField.duration),
                  ),
                  const VerticalRule(height: _headerHeight),
                ],
                if (showDetails) ...[
                  const Expanded(
                    flex: _artistFlex,
                    child: SortableHeader(
                      'Artist',
                      LibrarySortField.albumArtist,
                    ),
                  ),
                  const VerticalRule(height: _headerHeight),
                  const Expanded(
                    flex: _albumFlex,
                    child: SortableHeader('Album', LibrarySortField.album),
                  ),
                  const VerticalRule(height: _headerHeight),
                ],
                if (showEverything) ...[
                  const SizedBox(
                    width: _releaseW,
                    child: SortableHeader(
                      'Release date',
                      LibrarySortField.releaseDate,
                    ),
                  ),
                  const VerticalRule(height: _headerHeight),
                  const SizedBox(
                    width: _dateW,
                    child: SortableHeader(
                      'Date added',
                      LibrarySortField.dateAdded,
                    ),
                  ),
                  // TODO: Add the Plays column after the initial release.
                ],
                // TODO: Add table settings after the initial release.
              ],
            ),
          ),
        );
      },
    );
  }
}

class SortableHeader extends StatelessWidget {
  const SortableHeader(
    this.label,
    this.field, {
    super.key,
    this.alignRight = false,
  });

  final String label;
  final LibrarySortField field;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      LibraryCubit,
      LibraryState,
      ({LibrarySortField field, LibrarySortDirection direction})
    >(
      selector: (state) =>
          (field: state.sortField, direction: state.sortDirection),
      builder: (context, sort) {
        final active = sort.field == field;
        final arrow = sort.direction == LibrarySortDirection.ascending
            ? Icons.arrow_drop_up
            : Icons.arrow_drop_down;

        return InkWell(
          onTap: () => context.read<LibraryCubit>().setSort(field),
          child: Row(
            mainAxisAlignment: alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Flexible(
                child: HeaderLabel(
                  label,
                  active: active,
                  alignRight: alignRight,
                ),
              ),
              if (active) Icon(arrow, color: accentColor, size: 18),
            ],
          ),
        );
      },
    );
  }
}

class HeaderLabel extends StatelessWidget {
  const HeaderLabel(
    this.text, {
    super.key,
    this.active = false,
    this.alignRight = false,
  });

  final String text;
  final bool active;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: alignRight ? 0 : 14, right: 14),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? accentColor : mutedColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class HeaderIcon extends StatelessWidget {
  const HeaderIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(child: Icon(icon, color: mutedColor, size: 25));
  }
}

class VerticalRule extends StatelessWidget {
  const VerticalRule({super.key, this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: height, color: lineColor);
  }
}

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    this.isCurrent = false,
    this.isPlaying = false,
  });

  final Track track;
  final bool isCurrent;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _libraryLayoutFor(constraints.maxWidth);
        final usesMediaRow =
            layout == _LibraryLayout.compact ||
            layout == _LibraryLayout.minimal;
        final horizontalPadding = layout == _LibraryLayout.full ? _hPad : 16.0;
        final showNumber = layout != _LibraryLayout.minimal;
        final showLength = layout != _LibraryLayout.minimal;
        final showDetails =
            layout == _LibraryLayout.medium || layout == _LibraryLayout.full;
        final showEverything = layout == _LibraryLayout.full;
        final artworkSize = layout == _LibraryLayout.minimal ? 46.0 : 54.0;

        return Material(
          color: isCurrent
              ? accentColor.withValues(alpha: 0.09)
              : Colors.transparent,
          child: InkWell(
            hoverColor: Colors.white.withValues(alpha: 0.035),
            onDoubleTap: () => _play(context),
            child: Container(
              height: _rowHeight,
              decoration: BoxDecoration(
                border: Border(
                  bottom: const BorderSide(color: lineColor),
                  left: BorderSide(
                    color: isCurrent ? accentColor : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: usesMediaRow
                  ? _mediaRow(layout, artworkSize)
                  : Row(
                      children: [
                        if (showNumber) ...[
                          SizedBox(
                            width: _numW,
                            child: isCurrent
                                ? _PlayingIndicator(isPlaying: isPlaying)
                                : BodyCell(track.number, alignRight: true),
                          ),
                          const SizedBox(width: 1),
                        ],
                        Expanded(
                          flex: _trackFlex,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                ArtworkImage(
                                  artworkId: track.artworkId,
                                  size: artworkSize,
                                ),
                                const SizedBox(width: 14),
                                Expanded(child: _TrackTitle(track: track)),
                                if (track.hasBadge) ...[
                                  const SizedBox(width: 8),
                                  const TinyLinkedBadge(),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (showDetails) ...[
                          SizedBox(
                            width: _favW,
                            child: _FavoriteIcon(favorite: track.favorite),
                          ),
                          const SizedBox(width: 1),
                        ],
                        if (showLength) ...[
                          SizedBox(
                            width: _lengthW,
                            child: BodyCell(track.formatMilliseconds()),
                          ),
                          const SizedBox(width: 1),
                        ],
                        if (showDetails) ...[
                          Expanded(
                            flex: _artistFlex,
                            child: LinkCell(track.artist),
                          ),
                          const SizedBox(width: 1),
                          Expanded(
                            flex: _albumFlex,
                            child: LinkCell(track.album, secondary: true),
                          ),
                          const SizedBox(width: 1),
                        ],
                        if (showEverything) ...[
                          SizedBox(
                            width: _releaseW,
                            child: BodyCell(track.releaseDate),
                          ),
                          const SizedBox(width: 1),
                          SizedBox(
                            width: _dateW,
                            child: BodyCell(track.dateAdded),
                          ),
                          // TODO: Add the Plays column after the initial
                          // release.
                        ],
                        // TODO: Add per-track actions after the initial
                        // release.
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _mediaRow(_LibraryLayout layout, double artworkSize) {
    final minimal = layout == _LibraryLayout.minimal;
    final metadata = [
      if (track.artist.isNotEmpty) track.artist,
      if (track.album.isNotEmpty) track.album,
    ].join(' · ');

    return Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ArtworkImage(artworkId: track.artworkId, size: artworkSize),
            if (isCurrent)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrackTitle(track: track),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: mutedColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          track.formatMilliseconds(),
          style: const TextStyle(
            color: mutedColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!minimal) ...[
          const SizedBox(width: 10),
          _FavoriteIcon(favorite: track.favorite),
        ],
        // TODO: Add per-track actions after the initial release.
      ],
    );
  }

  void _play(BuildContext context) {
    final libraryTracks = context.read<LibraryCubit>().state.tracks;
    context.read<PlaybackCubit>().play(
      selectedTrack: track,
      queueTracks: libraryTracks,
    );
  }
}

class _TrackTitle extends StatelessWidget {
  const _TrackTitle({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return Text(
      track.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: textColor,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.18,
      ),
    );
  }
}

class _PlayingIndicator extends StatelessWidget {
  const _PlayingIndicator({required this.isPlaying});

  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Icon(
        isPlaying ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
        color: accentColor,
        size: 20,
      ),
    );
  }
}

class _FavoriteIcon extends StatelessWidget {
  const _FavoriteIcon({required this.favorite});

  final bool favorite;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: favorite ? 'Remove from favorites' : 'Add to favorites',
      child: Icon(
        favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: favorite ? accentColor : mutedColor,
        size: 22,
      ),
    );
  }
}

class TinyLinkedBadge extends StatelessWidget {
  const TinyLinkedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(16, 16),
      painter: _TinyLinkedBadgePainter(),
    );
  }
}

class _TinyLinkedBadgePainter extends CustomPainter {
  const _TinyLinkedBadgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = mutedColor.withValues(alpha: .48)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = mutedColor.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(size.width * .35, size.height * .32), 3.4, paint);
    canvas.drawCircle(Offset(size.width * .68, size.height * .66), 3.4, paint);
    canvas.drawLine(
      Offset(size.width * .43, size.height * .42),
      Offset(size.width * .6, size.height * .57),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class BodyCell extends StatelessWidget {
  const BodyCell(this.text, {super.key, this.alignRight = false});

  final String text;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(left: alignRight ? 0 : 14, right: 14),
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: mutedColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class LinkCell extends StatelessWidget {
  const LinkCell(this.text, {super.key, this.secondary = false});

  final String text;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: secondary ? mutedColor : textColor.withValues(alpha: 0.88),
            fontSize: 16,
            fontWeight: secondary ? FontWeight.w500 : FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
