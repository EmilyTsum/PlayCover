# PTMC integration

This branch follows upstream PlayCover `develop` and bundles the public `EmilyTsum/PlayTools` `metal-capture` branch.

Pinned PlayTools commit at this revision: `b827781c54482861cf2ea2717bd2673f7ff79587`.

## User-facing control

PTMC remains implemented inside PlayTools in the game process. PlayCover owns configuration and control only:

- Every installed game has a **Metal Capture** tab in its existing App Settings sheet.
- Capture enablement, autostart, target FPS, HEVC bitrate, NV12 ring size, log interval, display-sync diagnostic, maximum-FPS spoof and output directory are persisted per game in `AppSettingsData`.
- Launch-time settings are passed directly to the game with `NSWorkspace.OpenConfiguration.environment`; no global `launchctl setenv` setup is required for the custom PlayCover build.
- Start, stop and status controls use bundle-targeted Darwin notifications such as `io.playcover.ptmc.start.<bundle-id>`, so two PTMC-enabled games do not have to start/stop together.
- `PTMC_OUTPUT_DIR` creates a new timestamped `.mov` for each recording. If no directory is selected, PlayTools uses the real user's `~/Movies` directory.

The PTMC options intentionally keep frame-pacing overrides opt-in. `CAMetalLayer.displaySyncEnabled = NO` and `UIScreen.maximumFramesPerSecond` spoofing should be enabled only while diagnosing a game that still presents at 60 fps.

## Distribution

`.github/workflows/ptmc-nightly-build.yml` builds the current `ptmc-nightly` branch on `macos-latest`, bootstraps the exact PlayTools commit from `Cartfile.resolved`, verifies PTMC strings in both the Carthage product and bundled framework, ad-hoc signs the resulting app, creates a DMG and uploads it as an Actions artifact.

Official Sparkle updates are disabled on this branch so the upstream update feed cannot silently replace the PTMC build. Updates are distributed through this fork's GitHub releases/Homebrew tap instead.
