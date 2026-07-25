import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/library_state.dart';
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
const _playsW = 76.0;
const _moreW = 64.0;
const _trackFlex = 34;
const _artistFlex = 17;
const _albumFlex = 19;
const _headerHeight = 56.0;
const _rowHeight = 80.0;

class TrackLibrary extends StatelessWidget {
  const TrackLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LibraryTopBar(),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _hPad),
            child: LibraryTitle(),
          ),
          const SizedBox(height: 28),
          const TrackTableHeader(),
          Expanded(child: LibraryList()),
        ],
      ),
    );
  }
}

class LibraryList extends StatefulWidget {
  const LibraryList({super.key});

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
              final showFooter =
                  state.status == LibraryStatus.loadingMore ||
                  state.status == LibraryStatus.failure;

              return ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.zero,
                itemCount: state.tracks.length + (showFooter ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == state.tracks.length) {
                    if (state.status == LibraryStatus.loadingMore) {
                      return const _LoadingMoreIndicator();
                    }

                    return _LoadMoreError(
                      onRetry: context.read<LibraryCubit>().retry,
                    );
                  }

                  return TrackRow(track: state.tracks[index]);
                },
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
  const LibraryTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_hPad, 22, _hPad, 0),
      child: Row(
        children: [
          const Icon(Icons.chevron_left, color: mutedColor, size: 32),
          const Spacer(),
          Icon(
            Icons.bookmark_border,
            color: mutedColor.withValues(alpha: .95),
            size: 25,
          ),
          const SizedBox(width: 40),
          Icon(
            Icons.search,
            color: mutedColor.withValues(alpha: .95),
            size: 27,
          ),
          const SizedBox(width: 46),
          const CircleAvatar(
            radius: 17,
            backgroundColor: greenColor,
            child: Text(
              'J',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LibraryTitle extends StatelessWidget {
  const LibraryTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'My Tracks',
                    style: TextStyle(
                      color: textColor,
                      fontFamily: 'Georgia',
                      fontSize: 38,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: BlocSelector<LibraryCubit, LibraryState, int>(
                      selector: (state) => state.totalSize,
                      builder: (context, totalSize) => Text(
                        '$totalSize ${totalSize == 1 ? 'track' : 'tracks'}',
                        style: const TextStyle(
                          color: mutedColor,
                          fontSize: 17,
                          height: 1,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 34),
            ],
          ),
        ),
        const PlayNowButton(),
      ],
    );
  }
}

class PlayNowButton extends StatelessWidget {
  const PlayNowButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Row(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              color: accentColor,
              child: const Row(
                children: [
                  Icon(Icons.play_arrow, color: Colors.white, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Play now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: accentColor,
                border: Border(
                  left: BorderSide(color: backgroundColor, width: 2),
                ),
              ),
              child: const Icon(Icons.arrow_drop_down, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackTableHeader extends StatelessWidget {
  const TrackTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: lineColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _hPad),
        child: Row(
          children: [
            const SizedBox(
              width: _numW,
              child: HeaderLabel('#', alignRight: true),
            ),
            const VerticalRule(height: _headerHeight),
            const Expanded(flex: _trackFlex, child: HeaderLabel('Track')),
            const SizedBox(width: _favW, child: HeaderIcon(Icons.search)),
            const VerticalRule(height: _headerHeight),
            const SizedBox(width: _lengthW, child: HeaderLabel('Length')),
            const VerticalRule(height: _headerHeight),
            Expanded(
              flex: _artistFlex,
              child: Row(
                children: const [
                  Expanded(child: HeaderLabel('Album artist', active: true)),
                  HeaderSortIcon(),
                  SizedBox(width: 8),
                  Icon(Icons.search, color: mutedColor, size: 22),
                  SizedBox(width: 8),
                ],
              ),
            ),
            const VerticalRule(height: _headerHeight),
            Expanded(
              flex: _albumFlex,
              child: Row(
                children: const [
                  Expanded(child: HeaderLabel('Album')),
                  Icon(Icons.search, color: mutedColor, size: 22),
                  SizedBox(width: 8),
                ],
              ),
            ),
            const VerticalRule(height: _headerHeight),
            const SizedBox(
              width: _releaseW,
              child: HeaderLabel('Release date'),
            ),
            const VerticalRule(height: _headerHeight),
            const SizedBox(width: _dateW, child: HeaderLabel('Date added')),
            const VerticalRule(height: _headerHeight),
            const SizedBox(width: _playsW, child: HeaderLabel('Plays')),
            const VerticalRule(height: _headerHeight),
            const SizedBox(
              width: _moreW,
              child: HeaderIcon(Icons.settings_outlined),
            ),
          ],
        ),
      ),
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

class HeaderSortIcon extends StatelessWidget {
  const HeaderSortIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Icon(Icons.arrow_drop_up, color: accentColor, size: 18),
    );
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
  const TrackRow({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onDoubleTap: () {
        final libraryTracks = context.read<LibraryCubit>().state.tracks;

        context.read<PlaybackCubit>().play(
          selectedTrack: track,
          queueTracks: libraryTracks,
        );
      },
      child: Container(
        height: _rowHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: lineColor)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _hPad),
          child: Row(
            children: [
              SizedBox(
                width: _numW,
                child: BodyCell(track.number, alignRight: true),
              ),
              const SizedBox(width: 1),
              Expanded(
                flex: _trackFlex,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      ArtworkImage(artworkId: track.artworkId, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.18,
                          ),
                        ),
                      ),
                      if (track.hasBadge) ...[
                        const SizedBox(width: 8),
                        const TinyLinkedBadge(),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: _favW,
                child: Icon(
                  track.favorite ? Icons.favorite : Icons.favorite_border,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 1),
              SizedBox(width: _lengthW, child: BodyCell(track.length)),
              const SizedBox(width: 1),
              Expanded(flex: _artistFlex, child: LinkCell(track.artist)),
              const SizedBox(width: 1),
              Expanded(flex: _albumFlex, child: LinkCell(track.album)),
              const SizedBox(width: 1),
              SizedBox(width: _releaseW, child: BodyCell(track.releaseDate)),
              const SizedBox(width: 1),
              SizedBox(width: _dateW, child: BodyCell(track.dateAdded)),
              const SizedBox(width: 1),
              SizedBox(width: _playsW, child: BodyCell(track.plays)),
              const SizedBox(width: 1),
              const SizedBox(
                width: _moreW,
                child: Icon(Icons.more_horiz, color: mutedColor, size: 26),
              ),
            ],
          ),
        ),
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
            color: textColor,
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
  const LinkCell(this.text, {super.key});

  final String text;

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
          style: const TextStyle(
            color: accentColor,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
