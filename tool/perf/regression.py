import json,os
from common import ROOT,POLICY,Report,regression_pairs,EvidenceUnavailable,require
root=ROOT/'performance-inputs'
current_files=list(root.rglob('latency/results.json'))
current=json.loads(current_files[0].read_text()) if len(current_files)==1 else {}
baseline_files=list((ROOT/'performance-baseline').rglob('latency/results.json'))
baseline=json.loads(baseline_files[0].read_text()) if len(baseline_files)==1 else None
report=Report('regression',minimum_cases=50)
report.metrics.update(scope='Paired profile-APK UI latency regression against an explicitly retained matching baseline; 20% per-sample CI budget, not a production SLA',
    baseline_run=os.environ.get('BASELINE_RUN',''),current_source=current.get('source'),baseline_source=baseline.get('source') if baseline else None)
try:
    pairs=regression_pairs(current,baseline)
except EvidenceUnavailable as error:
    for index in range(50): report.blocked(f'Latency regression pair {index+1:02}',str(error))
else:
    for index,(after,before) in enumerate(pairs):
        ratio=after['measurements']['ui_ready_ms']/before['measurements']['ui_ready_ms']
        report.case(f'Latency regression pair {index+1:02}: {after["name"]}',
            lambda ratio=ratio:require(ratio<=POLICY['regression_max_ratio'],'Latency ratio exceeds configured CI comparison budget'),'Paired profile latency')
        if report.cases[-1]['status']=='PASS':report.cases[-1]['detail']=json.dumps({'ratio':ratio,'before_ms':before['measurements']['ui_ready_ms'],'after_ms':after['measurements']['ui_ready_ms']})
raise SystemExit(report.write())
