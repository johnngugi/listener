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

## Native migration baseline

The `baseline-*` corpus freezes FFmpeg behavior before the native macOS media
backend is introduced:

- 16-bit mono at 22.05 kHz, including a one-frame file;
- an empty 16-bit stereo stream;
- 8,193 stereo frames spanning the encoder's 4,608-frame FLAC block boundary;
- exact PCM for caller reads smaller than, equal to, and larger than a block;
- populated, mixed-case, and duplicate-equivalent Vorbis comments;
- standalone and embedded JPEG, PNG, and WebP covers.
- a 1500x1200 JPEG used to verify 1024-pixel artwork normalization.

`seekable-s16le-stereo.flac` supplies the seek oracle at frame zero, middle
frames, FLAC block boundaries, the final frame, and EOF. The tests also record
FFmpeg's existing `SeekFailed` result at frame 4,607, immediately before the
first block boundary.

Regenerate the baseline audio, PCM, tag, and artwork files with:

```sh
server/testdata/fixtures/regenerate-baseline.sh
```

The script requires `ffmpeg` and `cwebp`. Regeneration intentionally replaces
the golden files and should only be committed when reviewing an oracle change.
