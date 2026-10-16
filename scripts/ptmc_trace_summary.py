#!/usr/bin/env python3
"""Summarize ptmcctl trace files without mixing generations or treating stale snapshots as live."""
import argparse, json
from pathlib import Path
COUNTERS = ('presented','captured','encoded','presentGapsOverBudget','droppedPool','droppedGPU',
            'droppedResidency','droppedEncoder','droppedLate','samplingSkipped','nativeLinearViewFrames','previewSubmitted','previewPresented','previewSkipped')
PEAKS = ('maxPresentGapUs','maxCaptureHookUs','maxPresentCallUs','lastOwnedCaptureGPUTimeUs',
         'lastOwnedCaptureCompletionUs','maxEncoderQueueUs','maxVTCallbackUs','pendingWritesHighWater','pendingWriteBytes')
def summarize(path):
    rows = [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]
    metadata = next((r for r in rows if r.get('kind') == 'metadata'), {})
    groups = {}; missing = stale = 0
    seen = set()
    for row in rows:
        if row.get('kind') != 'sample': continue
        s = row.get('status', {})
        if not s or 'timestamp' not in s or 'generation' not in s:
            missing += 1; continue
        if row.get('statusAgeSeconds', -1) > 2.5: stale += 1
        key = (s['generation'], s['timestamp'])
        if key in seen: continue
        seen.add(key); groups.setdefault(s['generation'], []).append(s)
    report = {'file': str(path), 'label': metadata.get('label'), 'os': metadata.get('os'),
              'missingSamples': missing, 'staleSamples': stale, 'generations': []}
    for generation, samples in groups.items():
        samples.sort(key=lambda s:s['timestamp'])
        first,last = samples[0],samples[-1]
        elapsed = last['timestamp']-first['timestamp']
        deltas = {k:last[k]-first[k] for k in COUNTERS if k in first and k in last}
        resets = [k for k in COUNTERS if any(b.get(k,0)<a.get(k,0) for a,b in zip(samples,samples[1:]))]
        valid = elapsed > 0 and not resets
        report['generations'].append({'generation':generation, 'samples':len(samples), 'elapsedSeconds':elapsed,
            'validCounterWindow':valid, 'counterResets':resets, 'delta':deltas,
            'rates':{k:deltas[k]/elapsed for k in ('presented','captured','encoded','previewPresented') if valid and k in deltas},
            'peaks':{k:max(s[k] for s in samples if k in s) for k in PEAKS if any(k in s for s in samples)},
            'presentationModes':sorted({(s.get('displaySync'),s.get('displaySuppressed'),s.get('displayPresentSkipped')) for s in samples},key=str)})
    return report
if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('traces',nargs='+'); args=p.parse_args()
    print(json.dumps([summarize(path) for path in args.traces],ensure_ascii=False,indent=2))
