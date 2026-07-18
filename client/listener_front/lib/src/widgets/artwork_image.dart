import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:listener_front/src/models/track.dart';
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/utils/result.dart';
import 'package:listener_front/src/widgets/album_art.dart';

class ArtworkImage extends StatefulWidget {
  const ArtworkImage({required this.artworkId, required this.size, super.key});

  final int? artworkId;
  final double size;

  @override
  State<ArtworkImage> createState() => _ArtworkImageState();
}

class _ArtworkImageState extends State<ArtworkImage> {
  Future<Result<ArtworkResponse>>? _artwork;

  @override
  void initState() {
    super.initState();
    _loadArtwork();
  }

  @override
  void didUpdateWidget(ArtworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.artworkId != widget.artworkId) {
      _loadArtwork();
    }
  }

  void _loadArtwork() {
    final artworkId = widget.artworkId;
    _artwork = artworkId == null
        ? null
        : context.read<ArtworkRepository>().get(artworkId);
  }

  @override
  Widget build(BuildContext context) {
    if (_artwork == null) {
      return AlbumArt(style: CoverStyle.eclipse, size: widget.size);
    }

    return FutureBuilder<Result<ArtworkResponse>>(
      future: _artwork,
      builder: (context, snapshot) {
        final artwork = snapshot.data;
        if (artwork == null) {
          return AlbumArt(style: CoverStyle.eclipse, size: widget.size);
        }

        switch (artwork) {
          case Ok<ArtworkResponse>():
            return Image.memory(
              artwork.value.data,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return AlbumArt(style: CoverStyle.eclipse, size: widget.size);
              },
            );
          case Error<ArtworkResponse>():
            return AlbumArt(style: CoverStyle.eclipse, size: widget.size);
        }
      },
    );
  }
}
