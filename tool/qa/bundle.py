import json, os
from pathlib import Path
import xlsxwriter
root=Path('qa-bundle'); root.mkdir(exist_ok=True)
jobs=json.loads(os.environ['QA_JOB_RESULTS'])
book=xlsxwriter.Workbook(root/'FINAL_TEST_SUMMARY.xlsx',{'strings_to_formulas':False,'strings_to_urls':False})
sheet=book.add_worksheet('EXECUTIVE SUMMARY')
head=book.add_format({'bold':True,'bg_color':'#183B56','font_color':'white'})
sheet.write_row(0,0,['VITALIS CI test programme â€” actual execution'],head)
sheet.write_row(3,0,['Suite','Job','Executed','Passed','Failed','Skipped','Minimum','Verdict'],head)
all_pass=True; rows=[]; reports=[]; problems=[]
for path in root.rglob('results.json'):
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data,dict): raise ValueError('report must be an object')
        reports.append(data)
    except (OSError,ValueError) as error:
        problems.append(str(path.relative_to(root))+': '+type(error).__name__)

for i,name in enumerate(['selenium','appium','bas','dast','load'],4):
    matches=[report for report in reports if report.get('suite')==name]
    report=matches[0] if len(matches)==1 else {}
    count=report.get('counts',{})
    cases=report.get('cases',[])
    actual={status:sum(c.get('status')==status for c in cases) for status in ['PASS','FAIL','SKIP']}
    passed=(not problems and jobs[name]['result']=='success' and report.get('status')=='PASS'
            and len(cases)>=300 and actual==count and actual['PASS']==len(cases))
    all_pass=all_pass and passed
    row=[name,jobs[name]['result'],len(report.get('cases',[])),count.get('PASS',0),count.get('FAIL',0),count.get('SKIP',0),300,'PASS' if passed else 'HOLD']
    sheet.write_row(i,0,row); rows.append(row)
sheet.set_column(0,1,28); sheet.set_column(2,7,18)
sheet.write_row(11,0,['Programme verdict','PASS' if all_pass else 'HOLD'])
sheet.write_row(13,0,['Scope','See each suite: browser/API contracts, UI scenarios, defensive BAS, native ingress DAST, sequential workload.'])
book.close(); (root/'FINAL_TEST_SUMMARY.json').write_text(json.dumps({'status':'PASS' if all_pass else 'HOLD','suites':rows,'report_integrity_problems':problems},indent=2))
with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:
    f.write('## VITALIS five-suite programme: '+('PASS' if all_pass else 'HOLD')+'\n\nDownload **VITALIS-Test-Execution-Reports-Bundle** for the executive workbook and every suite workbook, HTML/CSV/JSON report and raw evidence.\n')
raise SystemExit(0 if all_pass else 1)
