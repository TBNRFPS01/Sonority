# Verification record

Recorded 16 October 2026 in the Windows workspace. Source review and project checks do not establish Apple runtime behavior.

| Check | Result |
| --- | --- |
| Environment discovery | Windows NT 10.0.26300; Node/Git found; Swift, xcodebuild, xcrun unavailable |
| Project generation | Successful: app, widget, unit-test targets and shared scheme |
| Project integrity | 9/9 checks passed |
| XML parsing | App/widget Info plists, optional entitlements, shared scheme parsed successfully |
| Icon | Original 1024×1024 RGB asset generated and visually inspected |
| Fixtures | Both WAVs decoded with Python's wave reader: 8.0 seconds, correct mono/44.1 kHz and stereo/48 kHz headers; never auto-loaded |
| PNG integrity | Pillow verified the original icon file; it is RGB without an alpha channel |
| Additional Swift syntax parser | Not available; optional dependency download failed because package-host DNS was unavailable |
| Swift core tests | 11 written; not executed because Swift is unavailable |
| Native compile/link/simulator tests | Not run: no Apple toolchain |
| Native UI visual/accessibility review | Not performed: no simulator/iPad |
| Local audio/background/route tests | Not performed: no Apple runtime/device |
| Spotify | Not tested: no client ID, callback domain, authorized account |
| macOS CI | Workflow included; not dispatched or executed |
| Signing/archive/deployment | Not performed: no signing identity or iPad |

Node checks cover project reference resolution, source/config existence and inclusion, target phases, package/test registration, audio/orientation/URL declarations, configuration boundaries, Spotify/local separation, and shared test scheme presence. They do not parse/compile Swift or replace behavioral tests.

## XCTest coverage

`Tests/CoreTests.swift` contains eleven cases covering LRC fractions/offsets/repeated tags/translations, active-line boundaries, plain text, translation tolerance, Unicode/malformed timestamps, queue boundaries/repeat/removal/moves/duplicate occurrence selection, empty queues, model serialization, persistence round trips, corruption rejection, and future-version preservation. Run `swift test` on a supported Mac or Command-U in the shared Xcode scheme. No Swift pass result is asserted.

## Pending native acceptance

The following is an unexecuted acceptance procedure, not a record of passing tests.

1. Build with the README's simulator command; fix compiler/linker/asset failures, run core/Xcode tests, and record actual Xcode/SDK versions and results.
2. Launch an iPad simulator. Verify empty-library/lyrics/history states and no fictitious music.
3. Put the two WAVs from `Fixtures/` in Files, deliberately import them, and play at low volume. Verify durations and switching between mono/44.1 kHz and stereo/48 kHz.
4. Import owned MP3/AAC/ALAC/WAV files with embedded tags/artwork. Verify metadata, album/artist grouping, search, iCloud Drive imports, and graceful unsupported-file errors.
5. After import, revoke/remove originals and enable airplane mode. Confirm the sandboxed copies and imported lyrics remain playable/readable.
6. Exercise pause/resume, paused seeks, rapid seeks near the end, next/previous, repeat modes, shuffle, duplicate queue entries, selection/moves/deletion, and completion callbacks after switching tracks.
7. Create/edit/delete playlists, favorite/remove tracks, relaunch, and verify persistence. Confirm restoring the queue leaves playback paused.
8. Attach `TEST-TONE.lrc` and its translation. Verify highlights at 0/2/4/6 seconds, seek by tapping, aligned Spanish, follow toggle, full screen, clean mode, and untimed UTF-8 lyrics.
9. Measure local EQ/bass/preamp effects and real meter activity. Save/select profiles and relaunch. Maintain headroom and confirm Spotify is outside the processing path.
10. On a physical iPad, test locked-screen/background audio, system metadata/artwork and transport, headset controls, interruptions, and pause when headphones disconnect. Resume only when allowed by iPadOS.
11. Switch speakers/USB/Bluetooth/AirPods/AirPlay. Verify route/session values, no invented battery/model data, spatial flag, output picker, engine format-change recovery, and media-services reset messaging.
12. Verify history excludes deliberate paused/seek time, saves periodically, and survives relaunch. Test corrupted/future-version JSON without overwriting it. An abrupt kill may lose the last unsaved batch.
13. Review every screen in portrait/landscape, narrow split view, Stage Manager, large Dynamic Type, VoiceOver, keyboard navigation, and Reduce Motion. Fix actual clipping/contrast/focus issues revealed by Apple rendering.
14. Add the medium widget and verify player/import links. Confirm no fake live playback state is displayed.
15. Configure Spotify and test consent/denial/cancellation, associated-domain callback, invalid state, refresh, pagination, disconnect, offline errors, 403 access denial, and 429 limits. Opening Spotify should pause local playback.

Complete this run and distribution/privacy/provider-policy review before shipping. This deliverable is native source ready for its first Apple build, not a certified release.
