"""Combine the actual eight-suite evidence with one new 20-case volume suite."""
import hashlib,json,os,re,subprocess,sys,xml.etree.ElementTree as ET,zipfile
from common import ROOT,CATALOGUE,ALL_SUITES,case_count,require

root=ROOT/'qa-bundle';root.mkdir(exist_ok=True)
prior=os.environ['PRIOR_RUN'];require(prior.isdigit(),'Numeric prior run required')
problems=[];jobs={'host_volume':{'result':os.environ['VOLUME_JOB_RESULT']}}

def api(suffix):
    return json.loads(subprocess.run(['gh','api',f'repos/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{prior}'+suffix],check=True,capture_output=True,text=True,timeout=30).stdout)

try:
    run=api('');previous_jobs=api('/jobs?per_page=100')['jobs']
    require(run['status']=='completed' and run['conclusion']=='success','Retained eight-suite run did not complete successfully')
    for key,prefix in [('android_latency','Ordered Android latency'),('host_early','Ordered host early'),('android_extended','Four additional Android suites')]:
        matching=[job for job in previous_jobs if job['name'].startswith(prefix)]
        require(len(matching)==1 and matching[0]['conclusion']=='success','Required retained job not successful: '+key)
        jobs[key]={'result':'success'}
    for item in CATALOGUE:
        suite=item['name']
        if suite=='volume': continue
        matches=[]
        for path in (root/'retained-eight').rglob('results.json'):
            data=json.loads(path.read_text(encoding='utf-8'))
            if data.get('suite')==suite:matches.append((path,data))
        require(len(matches)==1,'Missing or duplicate retained suite: '+suite)
        path,data=matches[0];cases=data.get('cases',[])
        require(data.get('status')=='PASS' and len(cases)>=case_count(suite) and all(case['status']=='PASS' for case in cases),'Retained cases did not all pass: '+suite)
        require(len({case['id'] for case in cases})==len(cases) and data['counts']['PASS']==len(cases),'Retained counts/IDs disagree: '+suite)
        require(re.fullmatch('[a-f0-9]{40}',data.get('source','')),'Invalid retained source')
        diff=subprocess.run(['git','diff','--name-only',data['source'],'HEAD','--','lib','android','assets','third_party','pubspec.yaml','pubspec.lock','tool/toolchain_policy.json'],check=True,capture_output=True,text=True,timeout=30).stdout
        require(not diff.strip(),'Product source differs from retained tests: '+suite)
        expected_run=prior
        if data['source']!=run['head_sha']:
            provenance=json.loads((path.parent/'retained-evidence-provenance.json').read_text())
            expected_run=str(provenance['original_run'])
            require(provenance['accepted_by']==run['head_sha'] and provenance['original_results_sha256']==hashlib.sha256(path.read_bytes()).hexdigest(),'Retained evidence chain failed: '+suite)
        require(data.get('run_url')=='https://github.com/'+os.environ['GITHUB_REPOSITORY']+'/actions/runs/'+expected_run,'Retained run identity differs: '+suite)
        with zipfile.ZipFile(path.parent/'report.xlsx') as book:
            rows=ET.fromstring(book.read('xl/worksheets/sheet2.xml')).findall('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheetData/{http://schemas.openxmlformats.org/spreadsheetml/2006/main}row')
            require(len(rows)-1==len(cases),'Retained Excel count differs: '+suite)
except (AssertionError,OSError,ValueError,KeyError,subprocess.SubprocessError) as error:
    problems.append(type(error).__name__+': '+str(error))
for key in ['android_latency','host_early','android_extended']:
    jobs.setdefault(key,{'result':'unverified'})
(root/'EVIDENCE_PROVENANCE.json').write_text(json.dumps(dict(retained_run=prior,new_volume_run=os.environ.get('GITHUB_RUN_ID'),problems=problems,
    scope='Eight existing suite reports plus one newly executed volume suite. Original source/run identities remain unchanged.'),indent=2),encoding='utf-8')
(root/'READ_ME.txt').write_text('The top-level workbook is the final nine-suite/300-case report. retained-eight contains the earlier eight-suite snapshot, including its then-current exclusions. Those historical files were not rewritten. Only smoothness, concurrency and regression are excluded from the final programme.\n',encoding='utf-8')
subprocess.run([sys.executable,str(ROOT/'tool/perf/fill_missing.py')],check=True)
env={**os.environ,'QA_PROGRAMME':json.dumps(ALL_SUITES),'QA_JOB_RESULTS':json.dumps(jobs),'QA_EVIDENCE_PROBLEMS':json.dumps(problems),
     'QA_SCOPE':'Final 300-case programme: 280 retained executed cases plus 20 new volume cases; original provenance retained. Three suites user-excluded.'}
result=subprocess.run([sys.executable,str(ROOT/'tool/qa/bundle.py')],env=env)
raise SystemExit(result.returncode)
