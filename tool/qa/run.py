import json, os, subprocess, sys
from report import Report, ROOT, require

def bas(report):
    command=['./tool/run_gate.sh','test','--no-pub','--reporter=json','--concurrency=2','--test-randomize-ordering-seed=20261104']
    result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,timeout=3600)
    (report.out/'machine.jsonl').write_text(result.stdout,encoding='utf-8')
    (report.out/'runner-stderr.log').write_text(result.stderr,encoding='utf-8')
    sys.path.insert(0,str(ROOT/'tool/reporting'))
    from validation_report import parse_events
    from core_report import write_core_report
    cases,problems,terminal=parse_events(result.stdout,ROOT)
    # Keep the full root evidence and existing 300-case catalogue separate.
    require(result.returncode==0 and terminal and terminal.get('success') is True and not problems,str(problems))
    require(write_core_report({'cases':cases,'source':os.environ.get('GITHUB_SHA','local'),'run_url':os.environ.get('GITHUB_SERVER_URL','https://github.com')+'/'+os.environ.get('GITHUB_REPOSITORY','Faizze-PI/Vitalis')+'/actions/runs/'+os.environ.get('GITHUB_RUN_ID','local'),'status':'PASS','scope':'Full hosted root regression; defensive BAS subset reported separately','runner_elapsed_ms':terminal['time']},report.out),'Incomplete core catalogue')
    terms=['reject','unsafe','invalid','malformed','corrupt','failure','failed','cancel','race','rollback','wrong','mismatch','cannot','prevents','denied','quarantine','traversal','overflow','timeout','unavailable','missing','untrusted','attack','oversized','bounds','bound','disposal','disposed','interrupted','unknown','limit','stale','duplicate','uninstall','preserve','protect','non-finite','never','refuses','error']
    selected=[c for c in cases if any(t in c['name'].lower() for t in terms)]
    for i,c in enumerate(selected): report.cases.append(dict(id=f'BAS-{i+1:03}',category=c['file'],name=c['name'],status=c['status'],duration_ms=c['duration_ms'],detail=c['file']))
    report.metrics.update(full_root_cases=len(cases),scope='Named adversarial/failure/lifecycle regressions selected from actual VITALIS source tests; complete runner and unchanged core-300 mapping retained separately. Application-level defensive BAS, not an enterprise endpoint-agent simulation.')

def main():
    report=Report(os.environ['QA_SUITE'])
    try:
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
