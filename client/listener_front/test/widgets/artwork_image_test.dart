import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listener_front/src/generated/listener/v1/listener.pbgrpc.dart'
    as grpc;
import 'package:listener_front/src/repositories/artwork_repository.dart';
import 'package:listener_front/src/widgets/artwork_image.dart';

void main() {
  testWidgets('fetches and displays artwork for the supplied ID', (
    tester,
  ) async {
    late grpc.GetArtworkRequest request;
    final repository = ArtworkRepository((value) async {
      request = value;
      return grpc.GetArtworkResponse(
        artworkId: Int64(42),
        mimeType: 'image/png',
        width: 1,
        height: 1,
        data: _transparentPng,
      );
    });

    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repository,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: ArtworkImage(artworkId: 42, size: 56),
        ),
      ),
    );
    await tester.pump();

    expect(request.artworkId, Int64(42));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('decodes artwork at its physical display size', (tester) async {
    final repository = ArtworkRepository((request) async {
      return grpc.GetArtworkResponse(
        artworkId: request.artworkId,
        mimeType: 'image/png',
        width: 1024,
        height: 768,
        data: _transparentPng,
      );
    });

    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repository,
        child: const MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ArtworkImage(artworkId: 42, size: 56),
          ),
        ),
      ),
    );
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    final resizedImage = image.image as ResizeImage;

    expect(resizedImage.width, isNull);
    expect(resizedImage.height, 112);
  });
}

final Uint8List _transparentPng = Uint8List.fromList([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0x3d,
  0x1d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);
