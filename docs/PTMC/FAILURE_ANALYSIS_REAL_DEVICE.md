# PlayCover PTMC Real Device Failure Analysis Report

## 1. Summary

This document records the root cause analysis and evidence collected from real Apple Silicon hardware running **PlayCover PTMC v0.1.3** and **PlayTools (metal-capture branch)**.

### Symptoms Reported
1. PlayCover launches and runs normally.
2. Capture settings UI is accessible and configurable.
3. Pre-compositor Metal Capture can be enabled.
4. Clicking "Start Recording" does not produce any video files (`.mov` / `.partial.mov`).
5. Runtime status does not continuously update during recording.
6. The macOS window output occasionally appears with HDR/EDR-like overblown colors.
7. Enabling "Force SDR presentation while capturing" does not eliminate the HDR issue.

---

## 2. Root Cause Analysis

### Primary Root Cause: Metal Present Hooks Never Intercept Real Frame Submission

The capture failure (no recording output, 0 presented/captured frames) is caused by a failure to hook `presentDrawable:` methods on Apple Silicon Metal CommandBuffer instances.

#### Architectural Mechanism:
1. In `ptmc_discover_runtime_classes()`:
   ```objc
   for (int i = 0; i < count; i++) {
       Class cls = classes[i];
       if (class_conformsToProtocol(cls, @protocol(MTLCommandBuffer))) {
           installed += ptmc_install_one_hook(cls, @selector(presentDrawable:), (IMP)ptmc_present_drawable);
           installed += ptmc_install_one_hook(cls, @selector(presentDrawable:atTime:), (IMP)ptmc_present_drawable_at_time);
           installed += ptmc_install_one_hook(cls, @selector(presentDrawable:afterMinimumDuration:), (IMP)ptmc_present_drawable_after_duration);
       }
   }
   ```
2. On Apple Silicon macOS, the runtime class hierarchy for command buffers is:
   ```text
   AGXG...FamilyCommandBuffer (Concrete GPU driver class)
     └── IOGPUMetalCommandBuffer
           └── _MTLCommandBuffer (Base Metal class implementing presentDrawable:)
                 └── _MTLObjectWithLabel
                       └── NSObject
   ```
3. Objective-C Runtime Inspection:
   - `_MTLCommandBuffer` implements `presentDrawable:`, `presentDrawable:atTime:`, and `presentDrawable:afterMinimumDuration:`. However, **`class_conformsToProtocol(_MTLCommandBuffer, @protocol(MTLCommandBuffer))` evaluates to `NO`** at runtime. Therefore, `_MTLCommandBuffer` is excluded from hooking.
   - The concrete driver class `AGXG...FamilyCommandBuffer` evaluates `class_conformsToProtocol` as `YES`. However, it does not override `presentDrawable:` directly; it inherits the implementation from `_MTLCommandBuffer`.
4. In `ptmc_install_one_hook()`:
   ```objc
   static BOOL ptmc_class_implements_selector(Class cls, SEL selector, Method *methodOut) {
       unsigned count = 0;
       Method *methods = class_copyMethodList(cls, &count);
       // ... only checks methods directly declared on `cls` ...
   }
   ```
   Because `class_copyMethodList()` only returns methods declared directly on `AGXG...FamilyCommandBuffer`, inherited methods are not found. As a result, hooking `AGXG...FamilyCommandBuffer` fails.
5. Classes actually hooked (Total = 7):
   - `MTLToolsCommandBuffer` (3 hooks: `presentDrawable:`, `presentDrawable:atTime:`, `presentDrawable:afterMinimumDuration:`) [Debug tool only]
   - `MTL3On4CommandBuffer` (3 hooks) [Special bridge only]
   - `CAMetalLayer` (1 hook: `nextDrawable`)
6. **Result**:
   The actual GPU CommandBuffer instance used by the game during rendering never triggers `ptmc_record_present()`. The counters remain `present=0.00 fps`, `captured=0`, and the `PTMCSession` (VideoToolbox encoder & AVAssetWriter) is never armed.

---

### Secondary Root Cause: Scope and Color Space Handling of Force SDR

1. `forceSDR` check in `ptmc_next_drawable()` only executes when `_requested == YES` (active recording session):
   - During standby or before Start Recording is pressed, `wantsExtendedDynamicRangeContent` is not modified.
2. When Unity or other game engines configure wide gamut or HDR color spaces (e.g. `kCGColorSpaceITUR_2100_PQ`, `kCGColorSpaceExtendedLinearITUR_2020`, or Display P3):
   - Setting `wantsExtendedDynamicRangeContent = NO` alone does not normalize the layer's `colorspace` or pixel format back to standard sRGB.
   - The macOS WindowServer compositor continues to apply extended dynamic range tonemapping, causing visual HDR blown-out presentation even when the EDR property is 0.

---

## 3. Real Device Verification Matrix

### Environment
- **OS**: macOS 27.0 (Apple Silicon arm64)
- **PlayCover Version**: 3.1.0 (Build 856)
- **Target Application**: Unity-based iOS game bundle
- **PlayTools Binary**:
  - Bundled SHA256: `7c8729421d31113a01967f8e6fc1513e91b52a7a2eac2adb7c114001c35786da`
  - System SHA256: `7c8729421d31113a01967f8e6fc1513e91b52a7a2eac2adb7c114001c35786da`
  - Status: Matched (System framework is up-to-date)

### Process Environment Variables
The game process receives all PTMC environment variables correctly:
```text
PTMC_ENABLE=1
PTMC_STANDBY=1
PTMC_FPS=120
PTMC_BITRATE=120000000
PTMC_BUFFERS=6
PTMC_DISABLE_DISPLAY_SYNC=0
PTMC_FORCE_SDR_DISPLAY=1
PTMC_SPOOF_MAX_FPS=0
PTMC_OUTPUT_DIR=<HOME>/Library/Containers/io.playcover.PlayCover/Captures/<bundle-id>
PTMC_STATUS_FILE=<HOME>/Library/Containers/io.playcover.PlayCover/PTMC Status/<bundle-id>.plist
```

### Sanitized System Log Evidence
```text
[PlayTools] [PTMC] hooks enabled bundle=<bundle-id> fps=120 bitrate=120000000 buffers=6 disableDisplaySync=0 forceSDR=1 spoofMaxFPS=0 standby=1
[PlayTools] [PTMC] installed 7 new Metal hooks (total=7)
[PlayTools] [PTMC] start requested; capture will arm on the next supported drawable
[PlayTools] [PTMC] present=0.00 fps drawable=0x0 pixelFormat=-1 displaySync=1 framebufferOnly=0 captured=0 encoded=0.00 fps dropped_pool=0 dropped_encoder=0 dropped_late=0 unsupported=0 requested=1
[PlayTools] [PTMC] stop requested
```

### Runtime Class Hierarchy & Method Reflection Output
```text
Protocol: MTLCommandBuffer
Total runtime classes scanned: 10353

Class: AGXG...FamilyCommandBuffer
  class_conformsToProtocol(MTLCommandBuffer): True
  declared presents in class_copyMethodList: []

Class: IOGPUMetalCommandBuffer
  class_conformsToProtocol(MTLCommandBuffer): False
  declared presents in class_copyMethodList: []

Class: _MTLCommandBuffer
  class_conformsToProtocol(MTLCommandBuffer): False
  declared presents in class_copyMethodList: [
    'presentDrawable:options:',
    'presentDrawable:atTime:',
    'presentDrawable:afterMinimumDuration:',
    'presentDrawable:'
  ]
```

---

## 4. Ruled-Out Hypotheses

| Hypothesis | Result | Evidence |
| :--- | :--- | :--- |
| Environment variables not passed via `NSWorkspace` | **Ruled Out** | Process logs show `PTMC_ENABLE=1`, `PTMC_STANDBY=1`, `fps=120`, `forceSDR=1` loaded cleanly. |
| System `PlayTools.framework` is stale/older than bundled | **Ruled Out** | SHA256 of bundled and system framework binaries match identically. |
| Missing `LC_LOAD_DYLIB` in target executable | **Ruled Out** | `otool -l` confirms `/Users/.../Library/Frameworks/PlayTools.framework/PlayTools` load command. |
| Sandbox entitlement blocking capture directory write | **Ruled Out** | SBPL entitlement explicitly allows `(subpath ".../Library/Containers/io.playcover.PlayCover")`. |
| Darwin control notification failure | **Ruled Out** | `start requested`, `stop requested`, and `status` notifications are reliably received by observer. |

---

## 5. Recommended Remediation Plan

1. **Fix Metal Command Buffer Hook Discovery**:
   - Instead of checking only `class_conformsToProtocol(cls, @protocol(MTLCommandBuffer))`, also check classes that respond to `presentDrawable:` or inherit from `_MTLCommandBuffer`.
   - In `ptmc_install_one_hook`, use `class_getInstanceMethod(cls, selector)` or walk the superclass chain to hook the actual implementation, or dynamically add method implementations to derived classes via `class_addMethod` before swizzling.
2. **Expand Force SDR Presentation Scope**:
   - Evaluate SDR enforcement on `nextDrawable` whenever `PTMC_FORCE_SDR_DISPLAY` is active, rather than only when `_requested == YES`.
   - When enforcing SDR, ensure `CAMetalLayer.colorspace` is explicitly reset to standard sRGB (`kCGColorSpaceSRGB`) in addition to resetting `wantsExtendedDynamicRangeContent = NO`.
