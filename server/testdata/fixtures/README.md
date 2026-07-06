# FLAC Fixtures

These fixtures are tiny FFmpeg-generated FLAC files used by integration tests.
The `.raw` files are the exact source PCM bytes used to generate the `.flac`
fixtures. The `.expected*.pcm` files are the oracle bytes asserted after
Symphonia decode and the service's strict conversion path.

For the 16-bit fixture, source `s16le` and output `s16le` are byte-identical.
For the 24-bit fixture, source `s24le` is packed 3-byte PCM, while the service
outputs 24 valid bits in a 32-bit little-endian container.

Regenerate with:

```powershell
ffmpeg -hide_banner -loglevel error -y -f s16le -ar 44100 -ac 2 -i tests\fixtures\strict-s16le-stereo.raw -c:a flac -sample_fmt s16 tests\fixtures\strict-s16le-stereo.flac
ffmpeg -hide_banner -loglevel error -y -f s24le -ar 96000 -ac 2 -i tests\fixtures\strict-s24le-stereo.raw -c:a flac -sample_fmt s32 tests\fixtures\strict-s24le-stereo.flac
```
