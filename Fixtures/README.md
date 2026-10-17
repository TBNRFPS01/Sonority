# Explicit test fixtures

These are generated test assets, **not music or demo library content**. They are never bundled or automatically imported.

- `TEST-TONE-44100-1ch.wav`: eight-second original 220 Hz mono PCM at 44.1 kHz.
- `TEST-TONE-48000-2ch.wav`: eight-second original 220/330 Hz stereo PCM at 48 kHz.
- `TEST-TONE.lrc`: four original timestamped test instructions.
- `TEST-TONE.translation.lrc`: matching Spanish translation.

Deliberately import the WAVs from Files, then attach the LRC files in Lyrics Studio. Begin at low system volume. These fixtures have no embedded tags/artwork; test metadata extraction separately with files you own. Recreate them with `node Scripts/generate-assets.mjs`.
