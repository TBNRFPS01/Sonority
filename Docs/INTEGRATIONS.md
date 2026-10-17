# Integrations and public API boundaries

Official documentation checked on 16 October 2026. No provider credentials, license agreement, or Apple hardware was available for live tests.

## Spotify

The application retrieves the connected user's playlists through the official Web API and opens returned Spotify HTTPS playlist links for playback. It requests `playlist-read-private` and `playlist-read-collaborative`. Playlist results stay in memory and are cleared on disconnect.

Spotify recommends [Authorization Code with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow) for mobile clients. Sonority uses S256, cryptographically random verifier/state values, exact callback validation, Keychain storage, and token refresh. It contains no client secret. Current [redirect rules](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri) require HTTPS except for explicit loopback IP addresses.

### Configure authentication

1. Register a Spotify developer app and obtain its client ID. Register the exact callback `https://YOUR_DOMAIN/spotify/callback`.
2. In the **Sonority app target's** build settings, set `SPOTIFY_CLIENT_ID` and `SPOTIFY_CALLBACK_HOST`. The host is only a DNS hostname, without scheme/slash/path/port. The default `example.invalid` intentionally blocks authentication until configured.
3. Set the app target's `CODE_SIGN_ENTITLEMENTS` to `Config/Spotify.entitlements`. Add Associated Domains capability and provision it with your Apple team. These entitlements are optional so local playback can build without domain provisioning.
4. Host `/.well-known/apple-app-site-association` over valid HTTPS on your domain. Replace the team ID and bundle ID placeholders below:

```json
{
  "webcredentials": {
    "apps": ["YOUR_TEAM_ID.YOUR_APP_BUNDLE_ID"]
  },
  "applinks": {
    "details": [{
      "appIDs": ["YOUR_TEAM_ID.YOUR_APP_BUNDLE_ID"],
      "components": [{"/": "/spotify/callback"}]
    }]
  }
}
```

Apple's [HTTPS authentication callback API](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession/callback/https%28host%3Apath%3A%29) requires an associated domain. Sonority uses AuthenticationServices callback matching rather than accepting arbitrary incoming universal links as authorization. Reinstall after association/provisioning changes and verify on a physical iPad. The callback domain must be yours to control.

5. Add test users to the Spotify app's allowlist. Test connect, consent cancellation, token expiration, playlists/pagination, external opening, disconnect, and API/network errors.

Current [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes) require a Premium app owner in development mode and permit up to five allowlisted authenticated users. The [July 2026 changes](https://developer.spotify.com/documentation/web-api/references/changes/july-2026) permit up to 25 client IDs per developer account while sharing development quotas across the account. Do not use an outdated one-client-ID assumption. Broader access remains subject to Spotify approval/policy.

### Playback boundary

Spotify's [iOS App Remote SDK](https://developer.spotify.com/documentation/ios/getting-started) can control playback in an installed Spotify app under its account, authorization, and device requirements. The [official SDK repository](https://github.com/spotify/ios-sdk) describes its lifecycle. App Remote is **not included** here; playlist browsing does not imply remote transport control.

Sonority does not obtain Spotify audio bytes, inspect protected downloads, process Spotify's stream with EQ, or synchronize lyrics to an unobserved external player. [Restricted recommendation/analysis capabilities](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api) are not recreated. Review Spotify branding, attribution, privacy, policy, and access requirements before release. Disconnect removes local credentials; server-side authorization can be revoked from the user's Spotify account.

## Apple audio and AirPods/output

[AVAudioEngine](https://developer.apple.com/documentation/avfaudio/avaudioengine) owns local processing. [AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession) configures playback and reports output/session information. Background audio is declared, but lock-screen, interruption, Bluetooth, and AirPlay behavior requires runtime testing.

| Capability | Sonority behavior |
| --- | --- |
| Choose output | Public `AVRoutePickerView` system UI |
| Output name/type | Read-only current-route output ports |
| Sample rate/channels/latency | Read-only session measurements; no Bluetooth codec or losslessness inference |
| Spatial capability flag | Read-only port report; no personalized Spatial Audio toggle or AirPods model inference |
| AirPods/case battery | Not supplied by the audio route API; no estimates shown |
| ANC/Transparency/Adaptive Audio/ear detection | Managed by system UI; no private APIs used |
| Personalized Spatial Audio | Managed by system UI |
| Head-tracking visualizations | Not implemented; a separate public Core Motion feature and permission review would be needed |

Apple documents the [current route](https://developer.apple.com/documentation/avfaudio/avaudiosession/currentroute) and [spatial port flag](https://developer.apple.com/documentation/avfaudio/avaudiosessionportdescription/isspatialaudioenabled). A user-editable route name does not authenticate a hardware model. The dashboard also reports non-Apple routes.

## Lyrics and licensing

The implemented path uses embedded `AVAsset` lyrics and user-selected UTF-8 LRC/text. It supports fractional timestamps, repeated tags, millisecond offsets, bilingual duplicate timestamps, and separate translation LRC matching. Plain text is readable but has no line seeking. User-imported lyrics persist locally for offline use.

No licensed online provider account, display agreement, translation rights, or cache permission was supplied. There is **no online lyrics request path or downloaded provider cache**. A future authorized provider should adapt into `LyricsDocument` only after its matching/display/attribution terms are established. Provider cache expiry/deletion must follow that agreement; indefinite user-import storage must not be reused for online content without permission.
