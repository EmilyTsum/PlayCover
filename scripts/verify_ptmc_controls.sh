#!/usr/bin/env bash
set -euo pipefail

app_file='PlayCover/Views/PlayCoverApp.swift'
settings_file='PlayCover/Model/AppSettings.swift'
view_file='PlayCover/Views/AppSettingsView.swift'

for file in "$app_file" "$settings_file" "$view_file"; do
  test -f "$file"
done

grep -Fq 'import Carbon.HIToolbox' "$app_file"
grep -Fq 'UInt32(kVK_ANSI_R)' "$app_file"
grep -Fq 'baseModifiers | UInt32(shiftKey)' "$app_file"
grep -Fq 'eligibleRunningApps().isEmpty' "$app_file"
grep -Fq 'unregisterHotKeys()' "$app_file"
grep -Fq 'applicationShouldTerminateAfterLastWindowClosed' "$app_file"
grep -Fq 'PTMCGlobalHotKeyManager.shared.finalizeBeforeQuit()' "$app_file"
grep -Fq 'NSApp.dockTile.badgeLabel = "REC"' "$app_file"
grep -Fq 'NSWorkspace.didLaunchApplicationNotification' "$app_file"
grep -Fq 'NSWorkspace.didTerminateApplicationNotification' "$app_file"

grep -Fq 'var metalCaptureGlobalHotkeysEnabled = true' "$settings_file"
grep -Fq 'var metalCaptureFeedbackSounds = true' "$settings_file"
grep -Fq 'begin_record' "$view_file"
grep -Fq 'end_record' "$view_file"
grep -Fq '⌥⌘R toggles recording' "$view_file"
grep -Fq 'PTMCGlobalHotKeyManager.shared.start(app: app, source: .interface)' "$view_file"
grep -Fq 'PTMCGlobalHotKeyManager.shared.stop(app: app, source: .interface)' "$view_file"

echo 'PTMC host controls invariants: PASS'
