# PTMC integration

This branch follows upstream PlayCover `develop` and bundles the public `EmilyTsum/PlayTools` `metal-capture` branch.

Pinned PlayTools commit at this revision: `64c956c10a2b76185682bed996c9fbb7f37aab53`.

## User-facing control

PTMC remains implemented inside PlayTools in the game process. PlayCover owns configuration and control only:

- Every installed game has a **Capture** section in its existing App Settings sheet.
- Capture enablement, autostart, target FPS, HEVC bitrate, NV12 ring size, log interval, display-sync diagnostic, maximum-FPS spoof and output directory are persisted per game in `AppSettingsData`.
- PlayCover writes a per-game PTMC runtime plist and also passes launch-time values through `NSWorkspace.OpenConfiguration.environment`; no global `launchctl setenv` setup is required.
- Start, stop and status controls use bundle-targeted Darwin notifications such as `io.playcover.ptmc.start.<bundle-id>`, so two PTMC-enabled games do not have to start/stop together.
- The sandboxed game stages `.partial.mov` / finalized `.mov` files under PlayCover's shared container, then PlayCover exports completed recordings to `~/Movies` or the selected destination.

The PTMC options intentionally keep frame-pacing overrides opt-in. `CAMetalLayer.displaySyncEnabled = NO` and `UIScreen.maximumFramesPerSecond` spoofing should be enabled only while diagnosing a game that still presents at 60 fps.

## Distribution

`.github/workflows/ptmc-nightly-build.yml` builds the current `ptmc-nightly` branch on `macos-latest`, bootstraps the exact PlayTools commit from `Cartfile.resolved`, verifies PTMC strings in both the Carthage product and bundled framework, ad-hoc signs the resulting app, creates a DMG and uploads it as an Actions artifact.

Official Sparkle updates are disabled on this branch so the upstream update feed cannot silently replace the PTMC build. Updates are distributed through this fork's GitHub releases/Homebrew tap instead.

## Real-device v0.1.4 fixes

Real-device analysis on Apple Silicon/macOS 27 found that concrete AGX command-buffer classes conform to `MTLCommandBuffer` but inherit `presentDrawable:*` from `_MTLCommandBuffer`, while `_MTLCommandBuffer` itself does not report protocol conformance. The previous own-method-only swizzle therefore never intercepted the game's real present path. PTMC now installs concrete overrides on conforming command-buffer classes when the present methods are inherited, preserving the inherited IMP for the tail call.

The same analysis ruled out environment propagation, stale PlayTools, missing injection, Darwin notification delivery, and sandbox write permissions. Runtime status now includes a one-second heartbeat and present-hook count so a broken hook path is visible without manually refreshing the UI.

SDR enforcement now applies whenever capture is enabled, not only after Start Recording. PTMC blocks EDR requests and normalizes `CAMetalLayer.colorspace` to standard sRGB while leaving the game's Metal pixel format untouched. The real-device evidence that motivated these changes is kept in `docs/PTMC/FAILURE_ANALYSIS_REAL_DEVICE.md`.

## Real-device capture path

PTMC now intercepts both `MTLCommandBuffer presentDrawable:*` and direct `CAMetalDrawable present*` submission paths. Unity titles observed on Apple Silicon use the latter directly. Frame-path hooks are installed lazily only when recording starts, implementation owners are deduplicated, and dormant wrappers use a fast-path so PTMC has near-zero overhead before the first recording.

The capture FPS setting is an actual sampling ceiling: a 120 Hz game captured at 60 fps skips conversion/encode work for intermediate presents instead of merely tagging the encoder as 60 fps. Video codecs are HEVC plus hardware-required Apple ProRes 422 LT / 422 / 422 HQ.

Game audio is captured separately by PlayCover with ScreenCaptureKit's application-level audio filter at 48 kHz stereo AAC, then muxed into the finalized PTMC MOV. No ScreenCaptureKit video frames are used by PTMC.

### Performance behavior

Frame-path hooks are installed only when Start Recording is requested. Direct `CAMetalDrawable.present*` is preferred on real-device Unity; command-buffer interception is only a fallback. On Stop, PTMC restores the original Metal method implementations, so the idle game returns to native dispatch with no per-frame PTMC wrapper. The UI reads the runtime heartbeat without continuously posting status notifications or rewriting configuration.

The Metal Performance HUD launch environment explicitly enables the HUD menu bar (`MTL_HUD_DISABLE_MENU_BAR=0`) whenever the per-app Metal HUD toggle is enabled.
