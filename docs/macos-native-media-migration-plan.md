# macOS Native Media Migration Plan

## Status

- Branch: `native-macos-media`
- Scope: macOS implementation only
- Long-term direction: platform-specific media backends behind cross-platform Zig interfaces
- Current decoder: FFmpeg
- Target decoder: macOS AudioToolbox
- Target artwork processor: macOS ImageIO

## Objective

Replace the server's FFmpeg dependency on macOS with Apple system frameworks while preserving the current streaming, seeking, metadata, and artwork behavior.

The migration will keep platform-neutral contracts and FLAC parsing code free of Apple-specific types. A future Windows backend should be addable without changing media consumers or rewriting the FLAC metadata parser.

## Non-goals

- Implementing or testing a Windows media backend in this branch
- Making the complete application build on Windows
- Adding support for audio formats other than those currently accepted by the library scanner
- Replacing the existing streaming protocol or output pipeline
- Changing stored library metadata or artwork schemas unless a compatibility issue requires it

## Design principles

1. Preserve the current `AudioDecoder` contract so callers do not need a platform rewrite.
2. Keep FLAC container parsing in pure Zig and independent of operating-system APIs.
3. Keep Apple framework types inside `server/media/macos/`.
4. Retain FFmpeg temporarily as a test oracle, not as a permanent fallback.
5. Remove FFmpeg only after native output passes byte-level and seek-level parity tests.
6. Reject malformed or oversized input before allocating based on untrusted lengths.

## Target layout

```text
server/media/
|-- decoder.zig          # Public API and compile-time platform selection
|-- types.zig            # Shared decoder types and errors
|-- artwork.zig          # Platform-neutral artwork contract
|-- flac/
|   `-- metadata.zig     # Cross-platform FLAC metadata parser
`-- macos/
    |-- decoder.zig      # AudioToolbox decoder
    `-- artwork.zig      # ImageIO validation and normalization
```

No empty Windows implementation will be added. A future backend can extend the platform switch with `windows/decoder.zig` and `windows/artwork.zig`.

## Compatibility contract

The migration must preserve the public behavior currently used by the server:

```zig
AudioDecoder.open()
AudioDecoder.read()
AudioDecoder.seekToFrame()
AudioDecoder.trackInfo()
AudioDecoder.deinit()
```

The native decoder must continue producing:

- signed 16-bit little-endian interleaved PCM for 16-bit sources;
- signed 32-bit little-endian interleaved PCM with 24 valid bits for 24-bit sources;
- signed 32-bit little-endian interleaved PCM for 32-bit sources;
- accurate frame counts and `end_of_stream` state;
- output that is independent of the caller's read-buffer size;
- frame-accurate seeking within the behavior supported by existing fixtures.

## Phase 1: Establish the FFmpeg baseline

Strengthen the tests before changing production behavior. FFmpeg output is the initial compatibility oracle.

Add or confirm fixtures covering:

- 16-bit mono and stereo FLAC;
- 24-bit stereo FLAC represented as 24 valid bits in 32-bit samples;
- supported sample rates and channel counts;
- empty, very short, and block-boundary files;
- reads smaller than, equal to, and larger than a decoded block;
- seeks to the first frame, middle frames, block boundaries, final frame, and EOF;
- complete PCM output and PCM returned after seeking;
- populated, missing, duplicated, and mixed-case tags;
- track and disc values in both `3` and `3/12` form;
- embedded JPEG, PNG, and WebP artwork;
- sidecar artwork selection and ranking;
- oversized, truncated, and malformed metadata and artwork.

Golden assertions should compare exact PCM bytes or stable hashes, not only frame counts.

### Exit criteria

- Existing behavior is represented by deterministic fixtures.
- Decoder tests exercise chunking, seeking, and EOF behavior.
- Metadata and artwork limits have regression coverage.

## Phase 2: Extract platform-neutral contracts

Move the following definitions out of the FFmpeg implementation into `server/media/types.zig`:

- `Options`
- `SampleFormat`
- `TrackInfo`
- `ReadResult`
- `PcmLayout`
- shared decoder errors where practical

Introduce `server/media/decoder.zig` as the import consumed by the rest of the server. During this phase it may still re-export the FFmpeg implementation.

Do not expose `AV*`, CoreAudio, CoreFoundation, or ImageIO types through the shared API.

### Exit criteria

- Media consumers import the shared decoder facade.
- The FFmpeg implementation still passes all tests.
- Shared modules compile without including FFmpeg or Apple headers.

## Phase 3: Implement the cross-platform FLAC parser

Create a bounded, pure-Zig parser for the FLAC metadata chain.

Parse:

- the `fLaC` stream marker;
- `STREAMINFO` for sample rate, channels, bits per sample, total samples, and MD5;
- `VORBIS_COMMENT` for library metadata;
- `PICTURE` for embedded artwork descriptors and encoded bytes.

Normalize the fields currently stored by the scanner:

- title;
- track artist;
- album artist;
- album;
- track number;
- disc number;
- release date;
- duration;
- codec name;
- sample rate;
- bits per sample;
- preferred front-cover artwork.

Parser requirements:

- validate every offset and length before reading;
- enforce existing metadata, artwork byte, dimension, and pixel limits;
- compare Vorbis-comment keys case-insensitively;
- handle `number/total` values without requiring the total;
- skip unknown metadata blocks safely;
- prefer a front-cover picture while retaining a deterministic fallback;
- return owned data with clear deinitialization rules;
- never trust picture dimensions without validation by the image backend.

### Exit criteria

- Parser unit tests run without FFmpeg or Apple frameworks.
- Existing metadata fixtures produce equivalent database fields.
- Truncated and adversarial lengths fail safely.

## Phase 4: Introduce the artwork abstraction

Define a platform-neutral artwork operation that accepts encoded bytes and returns validated, normalized artwork.

Responsibilities:

- detect the actual encoded format rather than trusting a filename or FLAC MIME field;
- validate dimensions and total pixels;
- reject invalid or excessively large inputs;
- preserve acceptable images where possible;
- resize artwork whose longest dimension exceeds 1,024 pixels;
- return accurate MIME type, dimensions, encoded bytes, and storage extension.

Implement the macOS backend using ImageIO and CoreGraphics. Both embedded artwork and sidecar artwork must pass through the same interface.

JPEG and PNG are required. The project's minimum supported macOS version is
12.0, where ImageIO also decodes the WebP fixture. JPEG, PNG, and WebP inputs
are therefore accepted; artwork requiring normalization is encoded as JPEG.

### Exit criteria

- Artwork behavior no longer depends on FFmpeg.
- Embedded and sidecar images share validation and normalization code.
- Existing size and dimension limits remain enforced.

## Phase 5: Implement the AudioToolbox decoder

Create `server/media/macos/decoder.zig` using Extended Audio File Services:

- `ExtAudioFileOpenURL`;
- `ExtAudioFileGetProperty`;
- `ExtAudioFileSetProperty`;
- `ExtAudioFileRead`;
- `ExtAudioFileSeek`;
- `ExtAudioFileDispose`.

The implementation must:

- convert the Zig path to a Core Foundation file URL safely;
- inspect the source format before choosing the client PCM format;
- request interleaved signed-integer PCM matching the compatibility contract;
- preserve the source's valid bit depth separately from its output container width;
- expose the total frame count when available;
- support arbitrary caller buffer sizes through a bounded pending buffer;
- distinguish a full read from the final full read without requiring an extra caller request;
- seek by source sample frame and reset all pending state;
- release every Core Foundation and AudioToolbox object on success and failure paths.

### Exit criteria

- The native decoder passes the existing decoder API tests.
- Resource cleanup passes repeated open/read/seek/close tests.
- No Apple types escape the macOS implementation module.

## Phase 6: Add temporary backend selection and parity tests

Status: implemented. `native` is the default on macOS; pass
`-Dmedia-backend=ffmpeg` to select the temporary FFmpeg oracle explicitly.

Add a temporary development option such as:

```text
-Dmedia-backend=ffmpeg
-Dmedia-backend=native
```

Use it to run both implementations against identical fixtures. Compare:

- `TrackInfo` fields;
- complete PCM bytes or SHA-256 hashes;
- PCM following each seek target;
- results across multiple caller buffer sizes;
- EOF transitions;
- errors for malformed and unsupported inputs;
- metadata values;
- artwork dimensions, MIME types, and normalized content expectations.

If AudioToolbox produces an intentional difference, document it and add an explicit test before accepting it.

Accepted differences:

- AudioToolbox reports `duration_frames = 0` for the valid empty FLAC fixture,
  while FFmpeg reports an unknown duration (`null`). Both report final-read EOF
  with no PCM bytes.
- AudioToolbox can seek to frame 4,607 in the seek fixture. FFmpeg's demuxer
  rejects that target immediately before its first 4,608-frame block boundary.
  All common seek targets produce identical PCM.
- For bytes that are neither valid FLAC nor another supported media container,
  FFmpeg may reach codec inspection and return `UnsupportedSampleFormat`, while
  AudioToolbox rejects the file during open with `CouldNotOpenInput`. Both reject
  the input before decoding or allocating PCM state.

### Exit criteria

- The native backend matches the agreed compatibility contract.
- Any accepted differences are documented and tested.
- Native is the default backend on macOS.

## Phase 7: Update the build

Update both the repository and standalone server build definitions.

Link the macOS frameworks required by the native implementation:

```zig
module.linkFramework("AudioToolbox", .{});
module.linkFramework("CoreFoundation", .{});
module.linkFramework("ImageIO", .{});
module.linkFramework("CoreGraphics", .{});
```

Keep platform selection based on the requested Zig target, not the host running the build.

For unsupported targets, fail at compile time with a clear message. Do not add placeholder Windows code.

### Exit criteria

- Clean macOS builds work without FFmpeg installed.
- The root integration tests and standalone server tests use the same backend configuration.
- The final executable has no FFmpeg load commands.

## Phase 8: Remove FFmpeg

After all parity and integration gates pass:

- delete the FFmpeg decoder implementation;
- remove FFmpeg imports from metadata and artwork code;
- remove FFmpeg include paths and library paths;
- remove `avformat`, `avcodec`, `avutil`, and `swscale` linkage;
- remove FFmpeg runtime search paths;
- remove FFmpeg bundle-copy and signing steps, if any were added;
- remove the temporary backend build option;
- search the repository for stale FFmpeg symbols and documentation;
- run tests on a machine or environment where FFmpeg is unavailable.

The manually compiled FFmpeg installation should remain available until this phase is complete so it can continue serving as the parity oracle.

### Exit criteria

- No application target imports, links, loads, or packages FFmpeg.
- All tests pass with Apple system frameworks only.
- The macOS application bundle contains no FFmpeg libraries.

## Validation commands

The exact commands may evolve with the build, but the migration should retain checks equivalent to:

```sh
zig build test
zig build -Doptimize=ReleaseSafe
rg 'libav|avcodec|avformat|avutil|swscale|ffmpeg' .
otool -L path/to/final/executable
```

The final `rg` output may contain this historical plan or other documentation, but must not identify active FFmpeg imports, linker settings, or packaging code.

## Risks and mitigations

### PCM representation differences

AudioToolbox may choose different native PCM container widths from FFmpeg. Set the client format explicitly and compare exact golden output.

### Seeking differences

Treat the requested source sample frame as the contract. Test block boundaries and final-frame behavior rather than relying only on duration-based timestamps.

### Metadata variation

Do not rely on platform metadata dictionaries. The pure-Zig FLAC parser is the source of truth for library fields.

### Artwork format differences

ImageIO support depends on the minimum macOS version. Require JPEG and PNG, test WebP explicitly, and document any intentional limitation.

### Long-running branch drift

Keep commits phase-oriented and regularly merge or rebase the target branch according to the repository's normal policy. Avoid mixing unrelated features into this branch.

## Commit strategy

Prefer reviewable commits that leave the branch buildable:

1. Add baseline fixtures and tests.
2. Extract shared media types and facade.
3. Add the cross-platform FLAC parser.
4. Add the artwork abstraction and ImageIO backend.
5. Add the AudioToolbox decoder.
6. Add parity selection and close behavioral gaps.
7. Switch macOS to the native backend.
8. Remove FFmpeg and its packaging configuration.

## Completion definition

The migration is complete when the macOS application builds and passes all tests without FFmpeg installed, emits PCM compatible with the existing streaming protocol, preserves library metadata and artwork behavior, performs frame-accurate seeking for the supported fixtures, and contains no FFmpeg runtime dependency.
