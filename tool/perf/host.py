"""Runs real product host workloads, retaining their measured results and errors."""
import json,os,subprocess,sys
from common import ROOT,POLICY,Report,require
sys.path.insert(0,str(ROOT/'tool/reporting'))
from validation_report import parse_events
suites=os.environ['PERF_SUITES'].split(','); failed=False
for suite in suites:
    report=Report(suite,minimum_cases=POLICY['cases'])
    metrics=report.out/'host-metrics.jsonl'
    env={**os.environ,'VITALIS_PERF_SUITE':suite,'VITALIS_PERF_METRICS':str(metrics)}
    command=['./tool/run_gate.sh','test','test_performance/qualification_test.dart','--no-pub','--concurrency=1','--reporter=json','--fail-fast']
    result=subprocess.run(command,cwd=ROOT,env=env,text=True,capture_output=True,timeout=1800)
    (report.out/'machine.jsonl').write_text(result.stdout,encoding='utf-8')
    (report.out/'runner-stderr.log').write_text(result.stderr,encoding='utf-8')
    cases,problems,terminal=parse_events(result.stdout,ROOT)
    observed={c['name'].rsplit(' ',1)[-1]:c for c in cases if suite+' sample ' in c['name']}
    measurements={str(r['case']):r for r in [json.loads(line) for line in metrics.read_text().splitlines()]} if metrics.exists() else {}
    for index in range(1,POLICY['cases']+1):
        key=str(index);name=f'{suite} sample {index}';case=observed.get(key)
        if case is None:
            report.blocked(name,'Runner did not complete this declared case; inspect machine.jsonl');continue
        row=dict(id=f'{suite.upper()}-{index:03}',category='Production host '+suite,name=name,
                 status=case['status'],duration_ms=case['duration_ms'],detail=case['file'])
        if row['status']=='PASS' and key not in measurements:
            row.update(status='FAIL',detail='Passing assertion has no corresponding measurement')
        if key in measurements: row['detail']=json.dumps(measurements[key])
        report.cases.append(row)
    report.metrics.update(immutable_model_sha256=os.environ.get('MODEL_SHA256'),scope='Real production host components; not target-phone performance',
        host_platform=sys.platform,runner_return_code=result.returncode,runner_problems=problems,
        measurements=list(measurements.values()))
    complete=result.returncode==0 and terminal and terminal.get('success') is True and not problems
    if not complete and all(c['status']=='PASS' for c in report.cases):
        report.cases[-1].update(status='FAIL',detail='Runner failed after cases; inspect raw output')
    failed=bool(report.write()) or failed
raise SystemExit(1 if failed else 0)
