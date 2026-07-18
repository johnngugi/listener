import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/utils/result.dart';

typedef GetArtworkCall =
    Future<grpc.GetArtworkResponse> Function(grpc.GetArtworkRequest request);

class ArtworkRepository {
  ArtworkRepository(this._getArtwork);

  factory ArtworkRepository.connect(grpc.ListenerLibraryClient libraryClient) {
    return ArtworkRepository(libraryClient.getArtwork);
  }

  final GetArtworkCall _getArtwork;

  Future<Result<ArtworkResponse>> get(int artworkId) async {
    Int64 artworkId64 = Int64(artworkId);

    try {
      final response = await _getArtwork(
        grpc.GetArtworkRequest(artworkId: artworkId64),
      );

      final artworkResponse = ArtworkResponse(
        mimeType: response.mimeType,
        width: response.width,
        height: response.height,
        data: Uint8List.fromList(response.data),
      );

      return Result.ok(artworkResponse);
    } on Exception catch (err) {
      return Result.error(err);
    }
  }
}

class ArtworkResponse {
  const ArtworkResponse({
    required this.mimeType,
    required this.width,
    required this.height,
    required this.data,
  });

  final String mimeType;
  final int width;
  final int height;
  final Uint8List data;
}
