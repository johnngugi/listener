#!/bin/sh
set -eu

fixture_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/listener-fixtures.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT HUP INT TERM

command -v ffmpeg >/dev/null
command -v cwebp >/dev/null

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'aevalsrc=sin(2*PI*440*t)*0.5:s=22050' \
  -af 'atrim=end_sample=17' -ac 1 -sample_fmt s16 -c:a flac \
  "$fixture_dir/baseline-s16le-mono-22050.flac"
ffmpeg -hide_banner -loglevel error -y \
  -i "$fixture_dir/baseline-s16le-mono-22050.flac" \
  -map 0:a:0 -f s16le \
  "$fixture_dir/baseline-s16le-mono-22050.expected.pcm"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'aevalsrc=sin(2*PI*330*t)*0.5:s=48000' \
  -af 'atrim=end_sample=1' -ac 1 -sample_fmt s16 -c:a flac \
  "$fixture_dir/baseline-one-frame-s16le-mono.flac"
ffmpeg -hide_banner -loglevel error -y \
  -i "$fixture_dir/baseline-one-frame-s16le-mono.flac" \
  -map 0:a:0 -f s16le \
  "$fixture_dir/baseline-one-frame-s16le-mono.expected.pcm"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'aevalsrc=sin(2*PI*220*t)*0.6|cos(2*PI*330*t)*0.4:s=48000' \
  -af 'atrim=end_sample=8193' -ac 2 -sample_fmt s16 -c:a flac \
  "$fixture_dir/baseline-block-boundary-s16le-stereo.flac"
ffmpeg -hide_banner -loglevel error -y \
  -i "$fixture_dir/baseline-block-boundary-s16le-stereo.flac" \
  -map 0:a:0 -f s16le \
  "$fixture_dir/baseline-block-boundary-s16le-stereo.expected.pcm"

touch "$scratch_dir/empty.raw"
ffmpeg -hide_banner -loglevel error -y \
  -f s16le -ar 44100 -ac 2 -i "$scratch_dir/empty.raw" -c:a flac \
  "$fixture_dir/baseline-empty-s16le-stereo.flac"
cp "$scratch_dir/empty.raw" "$fixture_dir/baseline-empty-s16le-stereo.expected.pcm"

ffmpeg -hide_banner -loglevel error -y \
  -i "$fixture_dir/baseline-s16le-mono-22050.flac" -map 0:a -c copy \
  -map_metadata -1 \
  -metadata 'TiTlE=Baseline Title' \
  -metadata 'ARTIST=Track Artist' \
  -metadata 'album_artist=Preferred Album Artist' \
  -metadata 'ALBUMARTIST=Fallback Album Artist' \
  -metadata 'AlBuM=Baseline Album' \
  -metadata 'TRACKNUMBER=3/12' \
  -metadata 'DISCNUMBER=2' \
  -metadata 'DATE=2026-08-31' \
  "$fixture_dir/baseline-metadata.flac"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'color=c=red:s=4x2' -frames:v 1 \
  "$fixture_dir/baseline-cover.jpg"
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i 'color=c=green:s=4x2' -frames:v 1 \
  "$fixture_dir/baseline-cover.png"
cwebp -quiet -lossless "$fixture_dir/baseline-cover.png" \
  -o "$fixture_dir/baseline-cover.webp"

for extension in jpg png webp; do
  ffmpeg -hide_banner -loglevel error -y \
    -i "$fixture_dir/baseline-s16le-mono-22050.flac" \
    -i "$fixture_dir/baseline-cover.$extension" \
    -map 0:a -map 1:v -c copy -disposition:v attached_pic \
    -metadata:s:v 'title=Album cover' \
    -metadata:s:v 'comment=Cover (front)' \
    "$fixture_dir/baseline-embedded-$extension.flac"
done
