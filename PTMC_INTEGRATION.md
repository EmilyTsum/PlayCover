# PTMC integration

This branch follows upstream PlayCover `develop` and bundles the public `EmilyTsum/PlayTools` `metal-capture` branch.

Pinned PlayTools commit at this revision: `d01eb6c94cf5919cd1bd51448bf9010c00b8d67a`.

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

The Metal Performance HUD is enabled by default for newly created app settings. Its launch environment explicitly keeps the HUD menu bar available (`MTL_HUD_DISABLE_MENU_BAR=0`) and enables the detailed avg/min/max value-range view (`MTL_HUD_SHOW_VALUE_RANGE=1`). Encoder timing is intentionally not forced because Apple documents additional HUD CPU overhead for that mode.

## CLI controller

On macOS, `scripts/ptmcctl.swift` provides direct runtime diagnostics without opening App Settings:

```sh
./scripts/ptmcctl.swift status com.example.game
./scripts/ptmcctl.swift start com.example.game
./scripts/ptmcctl.swift record com.example.game 10
./scripts/ptmcctl.swift config com.example.game fps=60 codec=prores422lt forceSDR=true
./scripts/ptmcctl.swift inspect com.example.game
```

The CLI uses the same targeted Darwin notifications and PTMC runtime plist as PlayCover. Audio recording remains host-owned by PlayCover because ScreenCaptureKit permission and per-application audio filtering belong to the host process.

For ProRes, PTMC uses a BGRA IOSurface ring and a direct Metal blit instead of running the full BGRA-to-NV12 compute conversion used by HEVC. This reduces PTMC GPU work; the Apple ProRes hardware encoder performs the required codec-side conversion.

The optimized capture path uses a 2×2 HEVC BGRA→NV12 compute kernel, a direct BGRA blit path for ProRes, one-time capture-layer normalization with restoration on Stop, and native Metal dispatch whenever recording is inactive.

### Capture resolution and GPU memory path

Capture resolution is independent from the game drawable. `source`, 2160p, 1440p, 1080p, 720p, and custom maximum-size modes preserve aspect ratio and never upscale. HEVC downscales while converting BGRA directly to the IOSurface-backed NV12 VideoToolbox input; ProRes downscales directly into an IOSurface-backed BGRA input. There is no CPU frame readback or intermediate full-frame CPU copy.

The optional experimental display-suppression mode sets only the capture CAMetalLayer opacity to zero while continuing to call the original present method so drawable recycling remains intact; Stop restores the original opacity and other presentation state.

### 4K frame-pacing / asynchronous encoder changes

The capture sampler now uses a deadline schedule with up to 1 ms of jitter tolerance. `samplingSkipped` is an intentional sampling count (for example, roughly 60 skips/s when a 120 Hz drawable is recorded at 60 fps), not an encoder failure. This also avoids the old edge case where slightly-early 60 Hz presents could be rejected every other frame.

VideoToolbox submission runs on a dedicated user-initiated serial queue. Its callback releases the raw IOSurface capture slot immediately, before disk/writer work. Compressed AVAssetWriter work is isolated on a separate utility queue, so storage backpressure no longer holds raw capture slots or blocks further VideoToolbox submission. The default capture ring is now 3 slots; larger rings remain available for experimentation.

### Metal HUD diagnostics default

New per-app settings default Metal HUD to enabled. At launch PlayCover keeps the macOS Metal HUD menu bar available and requests Apple's detailed value-range view (`MTL_HUD_SHOW_VALUE_RANGE=1`, with the current range key also enabled). PTMC does not force encoder timing or per-frame HUD logging because Apple documents additional HUD CPU cost for encoder timing; those heavier diagnostics remain opt-in from the Metal HUD menu/configuration panel. Existing saved per-app HUD choices remain unchanged.


### Near-target jitter handling

When the measured drawable cadence is effectively the requested capture rate, PTMC now accepts every present instead of applying a rate gate. This prevents small 60 Hz pacing jitter from becoming one/two-frame capture holes. Once the source is clearly faster than the target, PTMC switches to phase-preserving deadline sampling (for example 120→60 or 90→60).

The normal raw-frame ring remains 3 slots. One additional preallocated emergency IOSurface slot may be used at most once per 250 ms to absorb isolated VideoToolbox latency spikes, but it is cooldown-limited so sustained overload still drops rather than growing a deep queue and disturbing game rendering.


### Metal HUD capture policy

The Metal Performance HUD remains enabled by default for diagnostics, but capture now defaults to excluding it. PTMC uses Apple's documented `CAMetalLayer.developerHUDProperties` `mode=disabled` runtime control only while a recording is active, intercepts later HUD-property changes so the exclusion policy stays stable, and restores the layer's previous HUD dictionary on Stop. Enabling **Include Metal HUD in recording** leaves the HUD untouched so it can be burned into the captured video.

### Additional cleanup

Repeated Start commands no longer reset a live PTMC session or discard capture-layer restoration state. The direct-drawable Metal command queue is created during asynchronous session preparation instead of on the first captured frame. PlayCover also avoids a duplicate PTMC config write at launch, guarantees `isStarting` is cleared on every early-return/error path, uses asynchronous sleeps for app-lifecycle monitoring, and removes the stale `await` around the callback-based IPA picker.

The present hot path also caches the active `CAMetalLayer` address so unchanged frames avoid an atomic Objective-C property lookup/exchange, accesses `CAMetalDrawable.layer` directly, and folds the optional present-bypass decision into the existing capture pass instead of re-reading the drawable texture and manager state a second time.

PTMC also removes the per-frame Objective-C VideoToolbox callback-context allocation: callback metadata now lives on each preallocated IOSurface slot and is reused only after VideoToolbox releases that slot. This leaves the frame path without a per-frame PTMC context object allocation.
