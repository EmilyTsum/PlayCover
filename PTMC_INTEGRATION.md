# PTMC integration — maintainer source of truth

This file is the first document to read for the `ptmc-nightly` branch. It records the current architecture, invariants, accepted external patches, validation boundary, and release procedure. Do not reconstruct PTMC state from old CI logs, scratch files, or historical failure notes unless a regression specifically requires them.

## Current source pins

- PlayCover branch: `EmilyTsum/PlayCover:ptmc-nightly`
- PlayTools branch: `EmilyTsum/PlayTools:metal-capture`
- Pinned PlayTools commit: `ee13209dc51ca1722fa449927e6fed82daf882b3`
- Legacy overlay repository is retained only for reproducibility; it is not the active implementation.

`Cartfile.resolved` is authoritative for the PlayTools revision bundled into PlayCover. CI writes both PlayCover and PlayTools commit IDs into every DMG artifact.

## Capture architecture and non-negotiable invariants

PTMC captures inside the translated game process before WindowServer composition:

`Unity/game Metal drawable -> PTMC GPU copy/convert -> IOSurface-backed CVPixelBuffer ring -> VideoToolbox -> compressed CMSampleBuffer -> AVAssetWriter`

Keep these invariants unless real-device evidence justifies changing them:

- No ScreenCaptureKit video capture. ScreenCaptureKit is used only by PlayCover for target-application audio.
- No CPU frame readback (`getBytes`, full-frame memcpy, or equivalent).
- No per-frame raw-buffer allocation. Encoder inputs are preallocated IOSurface-backed CVPixelBuffers/CVMetalTextures.
- No per-frame Objective-C callback-context allocation. VideoToolbox callback metadata lives on the preallocated slot.
- No per-frame Objective-C class scan. Runtime hook discovery happens at recording activation / image-load discovery points.
- Never block the game's render/present thread on VideoToolbox or disk I/O. Overload drops capture work instead.
- Runtime present hooks are installed only while recording and original IMPs are restored on Stop.
- Direct `CAMetalDrawable.present*` interception is the primary Unity path observed on real hardware. `MTLCommandBuffer presentDrawable:*` remains a fallback.
- Supported source formats are currently BGRA8Unorm and BGRA8Unorm_sRGB. Do not claim HDR drawable-format support without implementing and testing it explicitly.

## GPU / encoder path

HEVC uses a 2x2 Metal compute kernel that converts BGRA directly into IOSurface-backed BT.709 video-range NV12. Scaling, when requested, is folded into that GPU conversion. VideoToolbox hardware acceleration is required, real-time mode is enabled, and frame reordering is disabled.

ProRes 422 LT / 422 / 422 HQ use IOSurface-backed BGRA buffers. Native-size capture is a direct Metal blit; scaled capture uses a Metal compute copy directly into the encoder buffer. There is no intermediate CPU image.

Capture resolution is independent of the game drawable. Modes are `source`, 2160p, 1440p, 1080p, 720p, and custom maximum dimensions. Aspect ratio is preserved and PTMC does not upscale above the source drawable.

VideoToolbox submission uses a dedicated user-initiated serial queue. Compressed writer work uses a separate utility queue. The raw slot is released in the VideoToolbox output callback before AVAssetWriter work, so disk pressure cannot retain scarce raw capture buffers.

## 4K frame pacing / backpressure

The normal raw ring defaults to 3 slots. A single additional preallocated emergency slot is cooldown-limited to absorb isolated encoder-latency spikes without turning the capture pipeline into a deep queue. `burstSlotUses` reports those recoveries.

The sampler distinguishes near-target jitter from real rate conversion. If the measured source cadence is effectively the requested capture rate, every present is accepted so small 60 Hz timing error does not become a 1/2-frame hole. When the source is clearly faster, PTMC uses a phase-preserving deadline sampler (for example 120 -> 60).

`samplingSkipped` is intentional target-FPS filtering, not an encoder failure. Runtime status exposes present/capture/encode FPS, sampling skips/s, raw in-flight frames, compressed pending writes, pool/encoder/late drops, burst recoveries, and owned capture-command timing.

The remaining user-reported target to validate on hardware is rare ~1–2 frame loss around 4K60. CI cannot prove this is eliminated; inspect the runtime counters on the user's Mac before making that claim.

## Presentation controls

Optional **Suppress on-screen output** makes only the capture CAMetalLayer transparent while continuing original present calls, allowing normal drawable recycling and potentially reducing visible compositor work.

Optional **Skip display present** bypasses forwarding the present after PTMC has captured it. This is deliberately marked unsafe because some games can starve/freeze their drawable pool. It must remain opt-in.

Display-sync disabling and UIScreen maximum-FPS spoofing are diagnostics, not defaults. Capture-layer framebuffer-only, display-sync, EDR, colorspace, opacity, and HUD state are restored on Stop.

## Metal HUD policy

Metal HUD is enabled by default for new app settings, with its menu bar kept available and detailed value-range metrics requested. Encoder timing is not forced because the diagnostic itself adds overhead.

**Include Metal HUD in recording** defaults off. While recording, PTMC attempts to suppress HUD composition on the active CAMetalLayer via the runtime `developerHUDProperties` selector when that selector exists, and restores the original dictionary on Stop. This selector is runtime/private-ish behavior rather than a compatibility guarantee; treat HUD exclusion as requiring real-device verification after OS updates.

PlayTools also includes upstream PR #229's fix that preserves the system Metal HUD menu item across UIKit main-menu rebuilds.

## Audio

PlayCover captures only the selected game's audio using ScreenCaptureKit application audio at 48 kHz stereo. It writes a temporary sidecar, then muxes it into the finalized PTMC MOV using the first video/audio host-time measurements and a passthrough AVAssetExportSession. No ScreenCaptureKit video output is subscribed. During recording, ScreenCaptureKit PCM samples are encoded to a 48 kHz stereo AAC sidecar using the known-good AVAssetWriter path, while a bounded 512-sample backlog absorbs short writer stalls and is flushed before finalization. Do not use `outputSettings = nil` for these ScreenCaptureKit PCM buffers: that mode caused the v0.1.9 video-only audio regression. v0.1.10 real-device evidence showed periodic tens-of-milliseconds zero-filled PCM despite continuous source PTS and zero writer drops/backpressure; the audio-only SCK configuration therefore keeps its tiny 2x2 internal screen work but uses a 1/60 minimum frame interval instead of the previous 1 fps throttle, with queue depth 8. Diagnostics now record writer drops, queue high-water mark, backpressure transitions, source-timestamp gaps, and >=10 ms near-zero PCM runs (`pcmZeroRuns`, total `pcmZeroMs`, and `pcmZeroMaxMs`). These zero-run counters are evidence of silence in the delivered PCM, not by themselves proof that ScreenCaptureKit synthesized the silence. Before muxing, PlayCover checks that the target volume has enough free space for the second passthrough movie plus a 1 GiB reserve; failed muxes preserve both the original video and audio sidecar. A completed mux is re-opened and required to contain both video and audio tracks before it can replace the original. The temporary `video-only.tmp.mov` step is a same-volume rename, not a third full copy, so an APFS clone is not useful for that replacement step; the dominant temporary allocation is the newly exported muxed movie itself.

The target Mac/game was re-tested after the 1/60 ScreenCaptureKit scheduler change and the user confirmed that the previously reproducible periodic audio interruption is no longer occurring. Keep the PCM zero-run counters enabled because this is real-device evidence for the current target, not a guarantee across every macOS release or application. A/V sync still requires separate real-device validation; CI only proves the code builds/packages.

## Capture workflow / operator controls

The PTMC host is designed to stay out of the way during repeated archive recording sessions:

- `⌥⌘R` globally toggles Start/Stop for the frontmost running PlayCover game. If no running PlayCover game is frontmost, the shortcut falls back only when exactly one capture-enabled game is running.
- `⇧⌥⌘R` is a stop/finalize-only shortcut for recovery when the operator wants to end a recording without reopening the settings window.
- Carbon hotkeys are registered only while at least one running game has PTMC capture and global shortcuts enabled, so PlayCover does not reserve those keys system-wide while no eligible game is running.
- Start/Stop feedback uses the macOS system `begin_record` / `end_record` sound assets when present, falling back to standard macOS sounds. Feedback originates from the PlayCover host, not the target-game application audio filter.
- The Dock tile shows `REC` while the host believes a PTMC recording is active.
- Closing the last PlayCover window no longer quits the host, so shortcuts and target-app audio can continue while the game is foreground. Explicit Quit still works.
- If PlayCover is running when an autostart-enabled game launches, the in-game runtime still owns video autostart while the host retries briefly until ScreenCaptureKit can attach the target-game audio stream.
- Explicitly quitting PlayCover while a host-tracked recording is active asks the capture to stop and waits for audio/finalization cleanup before allowing termination, reducing accidental sidecar/video loss.
- A low-staging-space warning is logged below 20 GiB; mux itself still performs the stricter file-size-aware preflight before creating a second passthrough movie.

These host controls do not alter the Metal present/encode hot path. The keyboard path only posts the same bundle-targeted Start/Stop commands used by the Capture settings UI.

## PlayCover host-side improvements

The PTMC fork also carries conservative host fixes that reduce unrelated stalls and macOS compatibility failures:

- app-library directory/Info.plist scanning moves off the main actor, then PlayApp objects are published in one main-actor batch;
- bundle-ID cache reconciliation is a single atomic merge/write instead of repeated reopen/append operations;
- icon extraction is cache-first and runs away from SwiftUI's main task;
- iTunes lookup is cache-first and coalesces duplicate in-flight requests;
- IPA temp-directory cleanup is guaranteed by `defer`, and temp replacement uses the system temporary directory;
- copied AKInterface extended attributes are cleared before ad-hoc signing to avoid FinderInfo/resource-fork codesign failures;
- macOS 27 launch aliases contain a real Info.plist while other top-level bundle items remain symlinks (upstream PR #2185);
- M5 iPad Pro / iPhone 17 Pro Max choices and matching PlayTools board IDs are included (upstream PRs #2187 / #231).

## Accepted upstream/fork patches

These were reviewed and intentionally incorporated rather than blindly merging a fork:

- PlayTools #229 — preserve Metal HUD menu after menu rebuild.
- PlayTools #233 — resolve the real account home directory with `getpwuid_r(getuid())`; removes the keymapping `/Users/<name>` assumption and avoids sandbox-container HOME confusion.
- PlayTools #232, first commit only — macOS 26 microphone permission synchronization through AVAudioApplication with legacy fallback. Its later path workaround was not taken because #233 supersedes it.
- PlayTools #231 / PlayCover #2187 — current M5 iPad Pro and iPhone 17 Pro Max device/board IDs.
- PlayCover #2185 — real Info.plist in launch alias for macOS 27 LaunchServices `-54` / `permErr` behavior.
- Kylinlixd PlayCover performance work — only the low-risk app-library/cache/icon/temp cleanup concepts were adapted. The fork's blanket macOS 26 deployment-target change and broad project rewrite were intentionally not imported.
- Kylinlixd signing cleanup — adapted as a narrowly scoped xattr cleanup immediately before signing the copied AKInterface bundle.

## Reviewed but intentionally deferred

- PlayTools #226 background keepalive: suppresses lifecycle events and runs silent audio; its own report notes quick-relaunch and OBS interactions. Too invasive for a default PTMC fork.
- PlayTools #227 privacy plist patch: mixes usage descriptions and an entitlement-like key in Info.plist. Do not copy it without separately validating the entitlement/signing path.
- PlayCover issue #2181 delayed-present workaround for ZZZ fullscreen 120 Hz: evidence is game-specific. Do not globally replace `present*AfterMinimumDuration` semantics without a per-game control and real-device proof.
- Full Kylinlixd macOS-26-only conversion: unnecessary for PTMC and would discard older supported macOS configurations without capture-specific benefit.

## Runtime control

Per-game Capture settings are written to a PTMC runtime plist and launch environment. UI and global-hotkey Start/Stop/status use the same bundle-targeted Darwin notifications (`io.playcover.ptmc.<command>.<bundle-id>`). The game writes partial/final MOVs under PlayCover's container; PlayCover exports completed files to `~/Movies` or the chosen directory. Global shortcut and feedback-sound preferences are host-only settings and are not injected into the game process.

`scripts/ptmcctl.swift` can inspect and control the same runtime on macOS:

```sh
./scripts/ptmcctl.swift status com.example.game
./scripts/ptmcctl.swift start com.example.game
./scripts/ptmcctl.swift record com.example.game 10
./scripts/ptmcctl.swift config com.example.game fps=60 codec=hevc resolution=2160p includeHUD=false
./scripts/ptmcctl.swift inspect com.example.game
```

Audio remains PlayCover-host-owned because ScreenCaptureKit permission/filtering belongs to the host process.

## Validation boundary

Automated validation can prove:

- PTMC static invariants / patch roundtrip / sampler model;
- Metal shader compilation;
- PlayTools macOS CI build and framework validation;
- PlayCover SwiftLint, CLI typecheck, app build, framework embedding, codesign, DMG creation;
- Homebrew installation and PlayCover startup smoke.

Automated validation **cannot** prove game-render FPS, rare 4K60 frame loss, HUD visibility/exclusion, actual VideoToolbox hardware behavior under sustained game load, or A/V sync. Those require the user's Apple Silicon Mac and a real game run.

## Release checklist

1. Both working trees clean; neither branch behind its upstream base.
2. PlayTools static + mac-build + SwiftLint succeed at the exact commit to ship.
3. Update `Cartfile.resolved` and this file to that exact PlayTools commit.
4. PlayCover SwiftLint + PTMC ad-hoc nightly succeed; artifact commit files match the intended PlayCover/PlayTools SHAs.
5. Verify DMG SHA-256, then tag/release PlayTools and PlayCover with the same PTMC version.
6. Update `EmilyTsum/homebrew-tap` cask to the released DMG SHA and require install/startup smoke success.
7. Remove temporary build/download files and temporary PR refs. Keep the legacy overlay repository intact.
