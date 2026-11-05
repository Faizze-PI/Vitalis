"""Reuse previously executed passes without changing their source or outcomes."""
import hashlib,json,os,re,subprocess,xml.etree.ElementTree as ET,zipfile
from common import ROOT,POLICY,case_count,require

def verify_report(data,suite,run_id):
    require(suite in ['latency','throughput','stress','spike'],'Only the four approved retained suites may be imported')
    require(str(run_id).isdigit(),'Numeric retained run required')
    require(data.get('suite')==suite and data.get('status')=='PASS','Retained suite did not pass')
    require(data.get('run_url')=='https://github.com/'+os.environ.get('GITHUB_REPOSITORY','Faizze-PI/Vitalis')+'/actions/runs/'+str(run_id),'Retained report belongs to another run')
    require(re.fullmatch('[a-f0-9]{40}',data.get('source','')),'Missing retained source identity')
    cases=data.get('cases',[])
    require(len(cases)>=case_count(suite) and all(c.get('status')=='PASS' for c in cases),'Retained cases are incomplete or not all passing')
    require(len({c.get('id') for c in cases})==len(cases),'Retained case IDs are duplicated')
    require(data.get('counts',{}).get('PASS')==len(cases) and not any(data.get('counts',{}).get(s,0) for s in ['FAIL','SKIP','BLOCKED']),'Retained counts are inconsistent')

def main():
    run_id=os.environ['COMPLETED_RUN'];suites=os.environ['PERF_SUITES'].split(',')
    jobs=json.loads(subprocess.run(['gh','api',f'repos/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{run_id}/jobs?per_page=100'],check=True,capture_output=True,text=True,timeout=30).stdout)['jobs']
    for suite in suites:
        folder=ROOT/'.qa-results'/suite;path=folder/'results.json';data=json.loads(path.read_text(encoding='utf-8'))
        verify_report(data,suite,run_id)
        phrase='Ordered Android latency' if suite=='latency' else 'Ordered host early'
        require(any(job['name'].startswith(phrase) and job['conclusion']=='success' for job in jobs),'Required retained job did not complete successfully')
        source=data['source']
        diff=subprocess.run(['git','diff','--name-only',source,'HEAD','--','lib','android','assets','third_party','pubspec.yaml','pubspec.lock','tool/toolchain_policy.json'],check=True,capture_output=True,text=True,timeout=30).stdout
        require(not diff.strip(),'Application/build/native source changed; cannot reuse earlier results')
        previous=json.loads(subprocess.run(['git','show',source+':tool/perf/policy.json'],check=True,capture_output=True,text=True,timeout=30).stdout)
        for key in ['policy_version','ui_action_budget_ms','native_context','native_batch','native_threads','native_output_tokens','stress_rows']:
            require(previous[key]==POLICY[key],'Retained workload policy differs: '+key)
        with zipfile.ZipFile(folder/'report.xlsx') as book:
            rows=ET.fromstring(book.read('xl/worksheets/sheet2.xml')).findall('{http://schemas.openxmlformats.org/spreadsheetml/2006/main}sheetData/{http://schemas.openxmlformats.org/spreadsheetml/2006/main}row')
            require(len(rows)-1==len(data['cases']),'Excel detail rows disagree with retained raw results')
        (folder/'retained-evidence-provenance.json').write_text(json.dumps(dict(
            scope='Retained executed evidence; not newly executed cases',original_run=run_id,original_source=source,
            accepted_by=os.environ.get('GITHUB_SHA'),original_results_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            product_source_unchanged=True,case_count=len(data['cases'])),indent=2),encoding='utf-8')
        with open(os.environ['GITHUB_STEP_SUMMARY'],'a',encoding='utf-8') as summary:
            summary.write(f'## {suite}: retained {len(data["cases"])} verified passes\n\nOriginal evidence: {data["run_url"]}. Not executed again.\n')
if __name__=='__main__':main()
