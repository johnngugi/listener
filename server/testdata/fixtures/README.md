# FLAC fixtures

These tiny FLAC files exercise server metadata, decoding, conversion, seeking,
and LSTN integration tests.

- `.raw` files contain source PCM used to generate a fixture.
- `.flac` files are the encoded test inputs.
- `.expected*.pcm` files contain the exact PCM bytes expected from the server.

For the 16-bit fixture, source `s16le` and output `s16le` are byte-identical. For
the 24-bit fixture, Listener emits 24 valid bits left-justified in a four-byte
little-endian signed container.

The `baseline-*` corpus covers:

- 16-bit mono at 22.05 kHz, including a one-frame file;
- an empty 16-bit stereo stream;
- 8,193 stereo frames spanning the encoder's 4,608-frame FLAC block boundary;
- exact PCM for caller reads smaller than, equal to, and larger than a block;
- populated, mixed-case, and duplicate-equivalent Vorbis comments;
- standalone and embedded JPEG, PNG, and WebP covers.
- a 1500x1200 JPEG used to verify 1024-pixel artwork normalization.

`seekable-s16le-stereo.flac` supplies seek coverage at frame zero, middle
frames, FLAC block boundaries, the final frame, and EOF.

The encoded inputs and expected PCM are committed golden artifacts. Do not
overwrite them unless the decoder contract is intentionally changing, and run
`cd server && zig build test` after any fixture update.
