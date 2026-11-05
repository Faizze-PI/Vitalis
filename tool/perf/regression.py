import json,os,shutil,subprocess
from common import ROOT,POLICY,case_count,Report,regression_pairs,EvidenceUnavailable,require
from reuse import verify_report
root=ROOT/'performance-inputs'
current_files=list(root.rglob('latency/results.json'))
current=json.loads(current_files[0].read_text()) if len(current_files)==1 else {}
baseline_files=list((ROOT/'performance-baseline').rglob('latency/results.json'))
baseline=json.loads(baseline_files[0].read_text()) if len(baseline_files)==1 else None
report=Report('regression',minimum_cases=case_count('regression'))
report.metrics.update(candidate_run=os.environ.get('CANDIDATE_RUN',''),scope='Paired profile-APK UI latency regression against an explicitly retained matching baseline; 20% per-sample CI budget, not a production SLA',
    baseline_run=os.environ.get('BASELINE_RUN',''),current_source=current.get('source'),baseline_source=baseline.get('source') if baseline else None)
try:
    if current and baseline:
        verify_report(current,'latency',os.environ.get('CANDIDATE_RUN') or os.environ['GITHUB_RUN_ID'])
        verify_report(baseline,'latency',os.environ['BASELINE_RUN'])
        for record in [current,baseline]:
            changed=subprocess.run(['git','diff','--name-only',record['source'],'HEAD','--','lib','android','assets','third_party','pubspec.yaml','pubspec.lock','tool/toolchain_policy.json'],check=True,capture_output=True,text=True,timeout=30).stdout
            require(not changed.strip(),'Product source changed relative to measured inputs')
        shutil.copyfile(current_files[0],report.out/'candidate-measured-input.json')
        shutil.copyfile(baseline_files[0],report.out/'baseline-measured-input.json')
        report.metrics.update(candidate_apk_source=current['measurements']['apk_source'],baseline_apk_source=baseline['measurements']['apk_source'])
    pairs=regression_pairs(current,baseline)
except EvidenceUnavailable as error:
    for index in range(case_count('regression')): report.blocked(f'Latency regression pair {index+1:02}',str(error))
else:
    for index,(after,before) in enumerate(pairs):
        ratio=after['measurements']['ui_ready_ms']/before['measurements']['ui_ready_ms']
        report.case(f'Latency regression pair {index+1:02}: {after["name"]}',
            lambda ratio=ratio:require(ratio<=POLICY['regression_max_ratio'],'Latency ratio exceeds configured CI comparison budget'),'Paired profile latency')
        report.cases[-1]['detail']+=' '+json.dumps({'ratio':ratio,'before_ms':before['measurements']['ui_ready_ms'],'after_ms':after['measurements']['ui_ready_ms']})
raise SystemExit(report.write())
