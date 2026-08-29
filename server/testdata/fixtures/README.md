# FLAC fixtures

These tiny FLAC files exercise server metadata, decoding, conversion, seeking,
and LSTN integration tests.

- `.raw` files contain source PCM used to generate a fixture.
- `.flac` files are the encoded test inputs.
- `.expected*.pcm` files contain the exact PCM bytes expected from the server.

For the 16-bit fixture, source `s16le` and output `s16le` are byte-identical. For
the 24-bit fixture, FFmpeg reads packed three-byte `s24le`, while Listener emits
24 valid bits left-justified in a four-byte little-endian signed container.

From the repository root, regenerate the strict fixtures with:

```sh
ffmpeg -hide_banner -loglevel error -y \
  -f s16le -ar 44100 -ac 2 \
  -i server/testdata/fixtures/strict-s16le-stereo.raw \
  -c:a flac -sample_fmt s16 \
  server/testdata/fixtures/strict-s16le-stereo.flac

ffmpeg -hide_banner -loglevel error -y \
  -f s24le -ar 96000 -ac 2 \
  -i server/testdata/fixtures/strict-s24le-stereo.raw \
  -c:a flac -sample_fmt s32 \
  server/testdata/fixtures/strict-s24le-stereo.flac
```

Do not overwrite the expected PCM files unless the intended decoder contract has
also changed. Run `cd server && zig build test` after regenerating fixtures.
