# Upstream PR series

This file tracks changes from the PTMC fork that are suitable for upstreaming to `PlayCover/PlayCover` as small, reviewable pull requests. Keep these branches independent: do not combine them into one maintenance PR.

Base for all PlayCover branches below: current `PlayCover/PlayCover:develop` (`7ff3ffffee6588d6062cef22addc77dce9e66de1` when prepared on 2026-08-17).

## Ready branches

| Proposed PR | Fork branch | Commit | Scope | Validation |
| --- | --- | --- | --- | --- |
| Fix resilient per-app settings persistence | `upstream/fix-app-settings-persistence` | `4e3142bf` | Atomic plist writes, no write-back while decoding, preserve unreadable plist, retain bundle ID on reset | Fork SwiftLint PASS |
| Stabilize and move app-library refresh off main actor | `upstream/perf-app-library-refresh` | `ca124fa6` | Background directory/plist scan, cancelled stale refreshes, atomic bundle-ID cache reconciliation, preserve `PlayApp` identity while bundle is unchanged | Fork SwiftLint PASS |
| Sanitize copied PlayTools plugin before signing | `upstream/fix-playtools-plugin-xattrs` | `38bd8b3d` | Clear FinderInfo/resource-fork xattrs immediately before ad-hoc signing | Fork SwiftLint PASS |
| Guarantee IPA temporary-directory cleanup | `upstream/fix-installer-temp-cleanup` | `539e8361` | `defer` cleanup covers success, early return and thrown error | Fork SwiftLint PASS |
| Cache and deduplicate iTunes lookups | `upstream/perf-itunes-request-dedup` | `7cdf3601` | Cache-first lookup and actor-based in-flight request coalescing | Fork SwiftLint PASS |
| Use stable IPA temp/zip paths | `upstream/fix-ipa-temp-paths` | `d26ea110` | Use system temporary directory and absolute `/usr/bin/zip` | Fork SwiftLint PASS |
| Move app-icon extraction off the main actor | `upstream/perf-app-icon-loading` | `6e0e6a23` | Cache-first icon lookup, background extraction, return TIFF `Data` across task boundary | Fork SwiftLint PASS |

The branches are pushed to `EmilyTsum/PlayCover` and can be opened as separate upstream PRs without depending on PTMC.

## Suggested order

1. `fix-app-settings-persistence` — correctness and data-loss prevention first.
2. `perf-app-library-refresh` — removes UI stalls and fixes stale `PlayApp/AppSettings` object identity during refresh.
3. `fix-installer-temp-cleanup` and `fix-ipa-temp-paths` — small installer reliability fixes.
4. `fix-playtools-plugin-xattrs` — signing reliability.
5. `perf-itunes-request-dedup` and `perf-app-icon-loading` — independent responsiveness improvements.

Do not stack these branches before review unless upstream requests it. Keeping them independent makes regressions and backports easier to isolate.

## Current upstream PR review

The currently open upstream PRs were reviewed before taking additional code into the PTMC fork.

### Adopted or already covered

- PlayTools #229 — Metal HUD menu preservation: already integrated.
- PlayTools #231 / PlayCover #2187 — M5 device IDs: already integrated.
- PlayTools #232 — microphone-permission synchronization: the low-risk permission-sync portion is integrated; the later path workaround is superseded by the robust home-directory fix.
- PlayTools #233 — robust current-account home-directory resolution: integrated and reused by PTMC.
- PlayTools #222 — only the first, narrowly scoped `ChildButton` mouse-binding persistence fix was adopted. The rest of the 13-commit controller-alias/modifier feature set remains separate.

### Intentionally deferred

- PlayCover #2112 + PlayTools #218 — scroll-wheel mapping. The PR pair currently has requested changes and explicitly changes the persisted setting schema in a way that breaks compatibility with older PlayCover/PlayTools combinations. Do not import until a migration-compatible schema is defined.
- PlayTools #214 — generic HID controller bridge. Experimental and comparatively large; needs device coverage before becoming a default stability patch.
- PlayTools #225 — `isiOSAppOnMac` bypass. The proposed two-line change activates `loadEnvironmentBypass`, which also empties the process environment. If needed, split the `isiOSAppOnMac` override into a dedicated opt-in path instead of enabling the broader environment bypass.
- PlayTools #226 — background keepalive. The PR itself reports quick-relaunch breakage and OBS interaction and has requested changes. Not suitable for a stability-focused default.
- PlayTools #227 — privacy plist additions. Split and validate the privacy descriptions separately from signing/entitlement changes before adoption.
- PlayCover #1785 — package backup/import. Importer remains unfinished; not a stability patch.
- PlayCover #1816 — custom app folders. Feature work with requested changes; unrelated to PTMC stability.
- PlayCover #2099 — SwiftLint cleanup around `NSOpenPanel`; useful cleanup but no demonstrated runtime stability benefit, so lower priority than the branches above.

## PTMC-specific upstreaming boundaries

PTMC itself should not be proposed as one giant PR. If upstream is interested, split it by responsibility:

1. **PlayTools Metal capture core** — dormant-by-default Metal presentation interception, IOSurface buffer ring, VideoToolbox writer, no CPU readback.
2. **Capture codecs/scaling** — HEVC + ProRes and GPU-only scale/convert path.
3. **Runtime control/status** — bundle-targeted Darwin notifications, runtime plist, structured diagnostics.
4. **Engine compatibility** — dual `CAMetalDrawable` / `MTLCommandBuffer` presentation-path selection with first-path-wins deduplication.
5. **PlayCover host controls** — per-game settings, global recording shortcuts and safe finalization.
6. **Game-audio capture/mux** — ScreenCaptureKit application audio only, bounded writer backlog, diagnostics, safe mux replacement.

Each stage must remain usable without requiring the later stages, and the no-ScreenCaptureKit-video/no-CPU-readback/render-thread-nonblocking invariants must remain explicit.
