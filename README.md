# Sonority

A native iPad music application, created from zero in Swift and SwiftUI. The actual Xcode project, app entry point, local audio services, interface, core package, widget extension, and tests are included.

**Build status: native source implemented; Apple compilation and runtime behavior are unverified.** This workspace runs Windows (reported build 26300). Node and Git are available; Swift, Xcode, Apple SDKs, signing identities, and an iPad are unavailable. No `.ipa` or successful native build is claimed.

## Open and run on a Mac

1. Copy this entire folder to a Mac with Xcode 16 or newer and the iPadOS 18 or newer SDK. The app targets iPadOS 18+. The core package also supports macOS 14+.
2. Open `Sonority.xcodeproj`. Select the **Sonority** scheme and an installed iPad simulator. The project is already generated; Node, XcodeGen, CocoaPods, and Spotify SDK installation are unnecessary.
3. Build and run. The first launch has an empty library. Choose **Import music** to select audio from Files.
4. For a physical iPad, select your development team for both app and widget targets. Change their bundle identifiers together: the widget identifier must start with the app identifier. Enable Developer Mode on the iPad and select it as the destination.
5. Spotify is optional and disabled until configured. Local playback needs no Spotify account or server. See [integration setup](Docs/INTEGRATIONS.md).

From this folder on a Mac:

```sh
swift test
xcodebuild -project Sonority.xcodeproj -scheme Sonority \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the scheme's tests with Command-U or select an installed simulator:

```sh
xcrun simctl list devices available
xcodebuild -project Sonority.xcodeproj -scheme Sonority \
  -destination 'platform=iOS Simulator,id=YOUR_INSTALLED_SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=NO test
```

Signing, archive/export, and deployment require the appropriate Apple credentials and provisioning. App Store release also requires device qualification, privacy/support information, and third-party branding/terms review.

## Implemented source

| Area | Implementation |
| --- | --- |
| Interface | SwiftUI split navigation, charcoal/forest/burgundy colors, material panels, cinematic/clean modes, artwork-average atmosphere, adaptive player layout, Dynamic Type, accessible control labels, Reduce Motion |
| Local music | Multi-file document import with security scope; sandbox copies; AVAudioFile decoding; AVAsset metadata/artwork/lyrics; albums/artists/search; favorites; playlists; imported-copy deletion |
| Playback | AVAudioEngine, play/pause, seek, previous/next, repeat, upcoming-queue shuffle, queue selection/reordering/removal, paused session restoration, missing-file errors |
| System media | Playback audio session, background-audio declaration, Now Playing metadata/artwork and remote commands, interruptions/route changes, system route picker |
| Lyrics Studio | Embedded and user-imported UTF-8 LRC/text; timed scrolling/seeking; original/translation matching; follow toggle; full screen; clean mode; local persistence |
| Spotify | Web API PKCE authentication, HTTPS callback/state validation, Keychain tokens, refresh, paginated user playlists, external Spotify links, disconnect, API errors |
| Sound Lab | Real five-band EQ, bass shelf/preamp, saved profiles, persisted active profile, real mixer RMS amplitude meter |
| AirPods/output | Genuine reported route name/type, session sample rate, channel count, output latency, spatial capability flag, system route picker |
| Ecosystem | Local listening time/history/most-played tracks, settings, persisted queue/position, medium WidgetKit quick-access widget, portrait/landscape and resizable scene |

These are source implementations, not verified device behavior. See [verification results](Docs/VERIFICATION.md).

## Architecture and storage

- `App/SonorityApp.swift`: entry point and service ownership.
- `App/LibraryStore.swift`: imports, metadata, artwork cache, library mutations, playlists, history, and user lyrics.
- `App/AudioPlayer.swift`: local engine, EQ, queue/session, metering, and system media integration.
- `App/SpotifyClient.swift`: independent authenticated Web API client. Spotify URLs never enter the local decoder.
- `Core/`: Foundation-only Codable models, queue state machine, LRC parser, and atomic JSON persistence.
- `Tests/`: eleven XCTest cases for important parser, queue, serialization, and disk behavior.
- `Widget/`: WidgetKit extension linking into the real app.
- `Config/`: property lists and optional Spotify entitlements.

Application Support contains `Sonority/library.json`, `Audio/`, `Artwork/`, and `Lyrics/`. Audio is copied into the sandbox for offline use. Unreadable/future-version libraries are preserved and writes blocked; restore a known-good `library.json` from backup before continuing. Queue, position, appearance, and active EQ use UserDefaults; OAuth credentials use Keychain.

Listening time is saved periodically, excluding deliberate pauses/seeks. An abrupt process kill can lose the latest unsaved batch. History retains up to 10,000 aggregated entries. No cloud library sync, analytics server, or Sonority account is included.

## Windows workflow

The committed project needs no generation. After adding/removing source files:

```powershell
node Scripts/generate-project.mjs
node Scripts/validate-project.mjs
```

Regeneration resets project customizations, including signing and Spotify settings. Make source-structure changes before configuring those settings, or retain your Xcode edits. `Scripts/generate-assets.mjs` recreates the original icon and labeled test fixtures. Fixtures are never bundled or automatically imported.

`.github/workflows/apple-build.yml` supplies macOS core tests and an unsigned simulator build. It has not been run. If this folder is nested in a repository, move the workflow to that repository's root `.github/workflows/` folder to activate it.

## Limitations

- No Apple compile, native UI rendering, runtime audio, background behavior, VoiceOver, or deployment was verified here. First-build framework errors may still require correction.
- Spotify playback is external. App Remote/Connect control, in-app Spotify streaming, recommendations, and protected-download access are not implemented.
- Online lyrics are not connected: a licensed provider agreement and credentials are missing. No unauthorized scraping or online lyrics caching is included.
- AirPods battery, ANC, Transparency, Adaptive Audio, and personalized Spatial Audio controls are unavailable in this implementation. The dashboard reports public route/session data only.
- The visualizer is an amplitude meter, not an FFT spectrum. EQ affects only Sonority's local audio. Boosts can clip without adequate preamp reduction.
- The widget opens app screens; it has no shared playback state or transport buttons and requires no app-group entitlement.
- Gapless playback, crossfade, ReplayGain, tag editing, folder monitoring, cloud sync, and automatic translation are not implemented.
- Decoder support depends on iPadOS. Protected files are unsupported; multichannel/high-resolution playback needs physical-device qualification.

See [API research and configuration](Docs/INTEGRATIONS.md) and the [native acceptance checklist](Docs/VERIFICATION.md).
