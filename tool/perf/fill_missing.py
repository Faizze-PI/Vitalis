"""Produce explicit per-case HOLD workbooks for jobs that never produced reports."""
import json,shutil
from common import ROOT,CATALOGUE,POLICY,Report
root=ROOT/'qa-bundle';root.mkdir(exist_ok=True)
known=set()
for path in root.rglob('results.json'):
    try: known.add(json.loads(path.read_text())['suite'])
    except (OSError,ValueError,KeyError,TypeError): pass # Original malformed evidence remains; bundle rejects it.
for item in CATALOGUE:
    if item['name'] in known: continue
    report=Report(item['name'],minimum_cases=POLICY['cases'])
    report.metrics['scope']='Generated prerequisite HOLD records, not executed test cases'
    for index in range(POLICY['cases']):report.blocked(f'{item["name"]} case {index+1}','No valid suite report from required job '+item['job'])
    report.write()
    shutil.copytree(report.out,root/'unavailable'/item['name'],dirs_exist_ok=True)
