#!/usr/bin/env python3
"""Regression fixtures: repeated heartbeat, missing status, stale file and a counter reset."""
import importlib.util,json,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('trace_summary',Path(__file__).with_name('ptmc_trace_summary.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def sample(g,t,n,age=0):
 return {'kind':'sample','statusAgeSeconds':age,'status':{'generation':g,'timestamp':t,'presented':n,'captured':n,'encoded':n}}
rows=[{'kind':'metadata','label':'fixture'},sample(1,10,20),sample(1,10,20),sample(1,12,140),
      sample(2,20,3),sample(2,21,2,4),{'kind':'sample','status':{}}]
with tempfile.TemporaryDirectory() as d:
 path=Path(d)/'fixture.jsonl';path.write_text('\n'.join(json.dumps(r) for r in rows))
 result=module.summarize(path)
 assert result['missingSamples']==1 and result['staleSamples']==1
 a,b=result['generations']
 assert a['samples']==2 and a['rates']['encoded']==60 and a['validCounterWindow']
 assert not b['validCounterWindow'] and b['rates']=={} and 'encoded' in b['counterResets']
print('PTMC trace summary fixtures: PASS')
