import json, os
from pathlib import Path
import xlsxwriter
root=Path('qa-bundle'); root.mkdir(exist_ok=True)
jobs=json.loads(os.environ['QA_JOB_RESULTS'])
definition=json.loads(os.environ.get('QA_PROGRAMME',json.dumps([dict(name=n,job=n,minimum=300) for n in ['selenium','appium','bas','dast','load']])))
programme=[item for item in definition if item.get('enabled',True)]
excluded=[dict(suite=item['name'],status='USER_EXCLUDED',reason=item.get('exclusion_reason','Excluded from selected programme')) for item in definition if not item.get('enabled',True)]
book=xlsxwriter.Workbook(root/'FINAL_TEST_SUMMARY.xlsx',{'strings_to_formulas':False,'strings_to_urls':False})
sheet=book.add_worksheet('EXECUTIVE SUMMARY')
head=book.add_format({'bold':True,'bg_color':'#183B56','font_color':'white'})
sheet.write_row(0,0,['VITALIS CI test programme - actual execution'],head)
sheet.write_row(3,0,['Suite','Job','Executed','Passed','Failed','Skipped','Blocked','Minimum','Verdict'],head)
all_pass=True; rows=[]; reports=[]; problems=[]
for path in root.rglob('results.json'):
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data,dict): raise ValueError('report must be an object')
        reports.append(data)
    except (OSError,ValueError) as error:
        problems.append(str(path.relative_to(root))+': '+type(error).__name__)

for i,item in enumerate(programme,4):
    name=item['name'];job=item.get('job',name);minimum=item['minimum']
    matches=[report for report in reports if report.get('suite')==name]
    report=matches[0] if len(matches)==1 else {}
    count=report.get('counts',{})
    cases=report.get('cases',[])
    actual={status:sum(c.get('status')==status for c in cases) for status in ['PASS','FAIL','SKIP']}
    blocked=sum(c.get('status')=='BLOCKED' for c in cases)
    if blocked or 'BLOCKED' in count: actual['BLOCKED']=blocked
    passed=(not problems and jobs[job]['result']=='success' and report.get('status')=='PASS'
            and len(cases)>=minimum and actual==count and actual['PASS']==len(cases))
    all_pass=all_pass and passed
    row=[name,jobs[job]['result'],actual['PASS']+actual['FAIL'],count.get('PASS',0),count.get('FAIL',0),count.get('SKIP',0),blocked,minimum,'PASS' if passed else 'HOLD']
    sheet.write_row(i,0,row); rows.append(row)
sheet.set_column(0,1,28); sheet.set_column(2,8,18)
sheet.write_row(len(programme)+6,0,['Programme verdict','PASS' if all_pass else 'HOLD'])
sheet.write_row(len(programme)+8,0,['Scope',os.environ.get('QA_SCOPE','See each suite: browser/API contracts, UI scenarios, defensive BAS, native ingress DAST, sequential workload.')])
if excluded:
    exclusions=book.add_worksheet('EXCLUDED SUITES')
    exclusions.write_row(0,0,['Suite','Status','Reason'],head)
    exclusions.set_column(0,1,24);exclusions.set_column(2,2,85)
    for index,item in enumerate(excluded,1):exclusions.write_row(index,0,[item['suite'],item['status'],item['reason']])
book.close(); (root/'FINAL_TEST_SUMMARY.json').write_text(json.dumps({'status':'PASS' if all_pass else 'HOLD','suites':rows,'report_integrity_problems':problems,'excluded_suites':excluded},indent=2))
with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:
    f.write('## VITALIS '+str(len(programme))+'-suite programme: '+('PASS' if all_pass else 'HOLD')+'\n\nDownload the combined Excel artifact for the executive workbook and every suite workbook, HTML/CSV/JSON report and raw evidence.\n')
raise SystemExit(0 if all_pass else 1)
