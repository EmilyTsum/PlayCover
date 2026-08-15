#!/usr/bin/env bash
set -euo pipefail

source_file='PlayCover/Views/AppSettingsView.swift'

test -f "$source_file"
grep -Fq 'configuration.sampleRate = 48_000' "$source_file"
grep -Fq 'configuration.channelCount = 2' "$source_file"
grep -Fq 'configuration.queueDepth = 8' "$source_file"
grep -Fq 'configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)' "$source_file"
grep -Fq 'private let maxPendingSamples = 512' "$source_file"
grep -Fq 'PTMC-Audio-active.m4a' "$source_file"
grep -Fq 'AVFormatIDKey: kAudioFormatMPEG4AAC' "$source_file"
grep -Fq 'AVEncoderBitRateKey: 256_000' "$source_file"
grep -Fq 'drainPendingSamples' "$source_file"
grep -Fq 'observePCMZeroRuns(sampleBuffer)' "$source_file"
grep -Fq 'pcmZeroMaxMs=' "$source_file"
grep -Fq 'hasSufficientMuxSpace(videoURL: videoURL, audioURL: audioResult.url)' "$source_file"
grep -Fq 'validateMuxedCapture(muxedURL)' "$source_file"

if grep -Fq 'configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)' "$source_file"; then
  echo 'PTMC audio must not throttle ScreenCaptureKit to 1 fps' >&2
  exit 1
fi

if grep -Fq 'outputSettings: nil' "$source_file"; then
  echo 'PTMC audio must not pass ScreenCaptureKit PCM samples through with nil outputSettings' >&2
  exit 1
fi

echo 'PTMC audio writer invariants: PASS'
