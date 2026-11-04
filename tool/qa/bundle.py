import json, os
from pathlib import Path
import xlsxwriter
root=Path('.qa-bundle'); root.mkdir(exist_ok=True)
jobs=json.loads(os.environ['QA_JOB_RESULTS'])
book=xlsxwriter.Workbook(root/'FINAL_TEST_SUMMARY.xlsx',{'strings_to_formulas':False,'strings_to_urls':False})
sheet=book.add_worksheet('EXECUTIVE SUMMARY')
head=book.add_format({'bold':True,'bg_color':'#183B56','font_color':'white'})
sheet.write_row(0,0,['VITALIS CI test programme — actual execution'],head)
sheet.write_row(3,0,['Suite','Job','Executed','Passed','Failed','Skipped','Minimum','Verdict'],head)
all_pass=True; rows=[]
for i,name in enumerate(['selenium','appium','bas','dast','load'],4):
    matches=[p for p in root.rglob('results.json') if json.loads(p.read_text()).get('suite')==name]
    report=json.loads(matches[0].read_text()) if len(matches)==1 else {}
    count=report.get('counts',{})
    passed=jobs[name]['result']=='success' and report.get('status')=='PASS' and len(report.get('cases',[]))>=300
    all_pass=all_pass and passed
    row=[name,jobs[name]['result'],len(report.get('cases',[])),count.get('PASS',0),count.get('FAIL',0),count.get('SKIP',0),300,'PASS' if passed else 'HOLD']
    sheet.write_row(i,0,row); rows.append(row)
sheet.set_column(0,1,28); sheet.set_column(2,7,18)
sheet.write_row(11,0,['Programme verdict','PASS' if all_pass else 'HOLD'])
sheet.write_row(13,0,['Scope','See each suite: browser/API contracts, UI scenarios, defensive BAS, native ingress DAST, sequential workload.'])
book.close(); (root/'FINAL_TEST_SUMMARY.json').write_text(json.dumps({'status':'PASS' if all_pass else 'HOLD','suites':rows},indent=2))
with open(os.environ['GITHUB_STEP_SUMMARY'],'a') as f:
    f.write('## VITALIS five-suite programme: '+('PASS' if all_pass else 'HOLD')+'\n\nDownload **VITALIS-Test-Execution-Reports-Bundle** for the executive workbook and every suite workbook, HTML/CSV/JSON report and raw evidence.\n')
raise SystemExit(0 if all_pass else 1)
