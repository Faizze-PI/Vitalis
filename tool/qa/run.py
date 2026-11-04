import json, os, subprocess, sys
from report import Report, ROOT, require

def bas(report):
    command=['./tool/run_gate.sh','test','--no-pub','--reporter=json','--concurrency=2','--test-randomize-ordering-seed=20261104','test','test_benchmarks']
    result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=3600,env={**os.environ,'VITALIS_VALIDATION_METRICS':str(report.out/'storage-metrics.jsonl')})
    (report.out/'machine.jsonl').write_text(result.stdout,encoding='utf-8')
    (report.out/'runner-stderr.log').write_text(result.stderr,encoding='utf-8')
    sys.path.insert(0,str(ROOT/'tool/reporting'))
    from validation_report import parse_events
    from core_report import write_core_report
    cases,problems,terminal=parse_events(result.stdout,ROOT)
    terms=['reject','unsafe','invalid','malformed','corrupt','failure','failed','cancel','race','rollback','wrong','mismatch','cannot','prevents','denied','quarantine','traversal','overflow','timeout','unavailable','missing','untrusted','attack','oversized','bounds','bound','disposal','disposed','interrupted','unknown','limit','stale','duplicate','uninstall','preserve','protect','non-finite','never','refuses','error']
    selected=[c for c in cases if any(t in c['name'].lower() for t in terms)]
    for i,c in enumerate(selected): report.cases.append(dict(id=f'BAS-{i+1:03}',category=c['file'],name=c['name'],status=c['status'],duration_ms=c['duration_ms'],detail=c['file']))
    report.metrics.update(full_root_cases=len(cases),scope='Named adversarial/failure/lifecycle regressions selected from actual VITALIS source tests; complete runner and unchanged core-300 mapping retained separately. Application-level defensive BAS, not an enterprise endpoint-agent simulation.')
    complete=result.returncode==0 and terminal is not None and terminal.get('success') is True and not problems and all(c['status']=='PASS' for c in cases)
    core_complete=write_core_report({'cases':cases,'source':os.environ.get('GITHUB_SHA','local'),
        'run_url':os.environ.get('GITHUB_SERVER_URL','https://github.com')+'/'+os.environ.get('GITHUB_REPOSITORY','Faizze-PI/Vitalis')+'/actions/runs/'+os.environ.get('GITHUB_RUN_ID','local'),
        'status':'PASS' if complete else 'FAIL',
        'scope':'Hosted root regression plus explicit storage benchmarks; BAS subset separate',
        'runner_elapsed_ms':terminal['time'] if terminal else 0},report.out)
    require(complete,'Runner failed, skipped or incomplete: '+str(problems))
    require(core_complete,'Incomplete core catalogue; actual completed cases retained')


def main():
    report=Report(os.environ['QA_SUITE'])
    try:
        require(not os.environ.get('QA_SETUP_FAILURE'),'Tooling or emulator setup failed; application checks did not run. Inspect retained Actions logs.')
        if report.suite=='bas': bas(report)
        elif report.suite=='selenium':
            from browser import run
            run(report)
        else:
            from mobile import run,dast,logs
            (dast if report.suite=='dast' else run)(report); logs(report)
    except Exception as error:
        message=f'{type(error).__name__}: {error}'
        report.case('Suite setup/completeness',lambda:require(False,message),'Infrastructure or completeness')
    return report.write()
if __name__=='__main__': raise SystemExit(main())
