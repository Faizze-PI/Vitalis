"""Execution-backed QA reports; failed/short suites cannot become green."""
import csv, html, json, os, time, traceback
from pathlib import Path
import xlsxwriter

ROOT=Path(__file__).resolve().parents[2]
class Report:
    def __init__(self,suite,minimum_cases=300):
        require(type(minimum_cases) is int and minimum_cases>0,"Positive case minimum required")
        self.minimum_cases=minimum_cases
        self.suite=suite; self.out=ROOT/'.qa-results'/suite; self.out.mkdir(parents=True,exist_ok=True)
        self.cases=[]; self.metrics={}; self.started=time.perf_counter()
    def case(self,name,action,category=None):
        start=time.perf_counter(); status='PASS'; detail=''
        try: action()
        except Exception as error:
            status='FAIL'; detail=f'{type(error).__name__}: {error}'
            (self.out/f'failure-{len(self.cases)+1}.txt').write_text(traceback.format_exc(),encoding='utf-8')
        self.cases.append(dict(id=f'{self.suite.upper()}-{len(self.cases)+1:03}',category=category or self.suite,
            name=name,status=status,duration_ms=(time.perf_counter()-start)*1000,detail=detail))
    def blocked(self,name,reason,category='Unavailable evidence'):
        self.cases.append(dict(id=f'{self.suite.upper()}-{len(self.cases)+1:03}',category=category,
            name=name,status='BLOCKED',duration_ms=0,detail=reason))
    def write(self):
        counts={s:sum(c['status']==s for c in self.cases) for s in ['PASS','FAIL','SKIP']}
        blocked=sum(c['status']=='BLOCKED' for c in self.cases)
        if blocked: counts['BLOCKED']=blocked
        executed=counts['PASS']+counts['FAIL']
        status='PASS' if len(self.cases)>=self.minimum_cases and all(c['status']=='PASS' for c in self.cases) else ('HOLD' if blocked else 'FAIL')
        result=dict(suite=self.suite,status=status,minimum_cases=self.minimum_cases,executed_cases=executed,source=os.environ.get('GITHUB_SHA','local'),
            run_url=os.environ.get('GITHUB_SERVER_URL','https://github.com')+'/'+os.environ.get('GITHUB_REPOSITORY','Faizze-PI/Vitalis')+'/actions/runs/'+os.environ.get('GITHUB_RUN_ID','local'),
            counts=counts,cases=self.cases,measurements=self.metrics,elapsed_seconds=time.perf_counter()-self.started)
        (self.out/'results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        book=xlsxwriter.Workbook(self.out/'report.xlsx',{'strings_to_formulas':False,'strings_to_urls':False})
        heading=book.add_format({'bold':True,'bg_color':'#183B56','font_color':'white','text_wrap':True})
        wrap=book.add_format({'text_wrap':True,'valign':'top','font_size':10})
        summary=book.add_worksheet('SUMMARY'); detail=book.add_worksheet('TEST RESULTS')
        summary.hide_gridlines(2); summary.set_column(0,0,34); summary.set_column(1,1,100,wrap)
        values=[('VITALIS '+self.suite,status),('Minimum cases',self.minimum_cases),('Executed',executed),('Case records',len(self.cases)),*counts.items(),
                ('Execution seconds',result['elapsed_seconds']),('Source',result['source']),('Evidence',result['run_url']),*[(key,json.dumps(value,ensure_ascii=False) if isinstance(value,(dict,list)) else value) for key,value in self.metrics.items()]]
        for row,values_row in enumerate(values): summary.write_row(row,0,list(values_row),heading if row==0 else wrap)
        row=len(values)+2; summary.write_row(row,0,['Module / category','Cases','Passed','Failed'],heading)
        groups={}
        for c in self.cases: groups.setdefault(c['category'],[]).append(c)
        for i,(name,cases) in enumerate(groups.items(),row+1): summary.write_row(i,0,[name,len(cases),sum(c['status']=='PASS' for c in cases),sum(c['status']=='FAIL' for c in cases)])
        headers=['Test ID','Category','Test Name','Objective','Preconditions','Steps','Test Data','Expected Result','Actual Result','Status','Priority','Severity','Time (ms)','Evidence','Remarks','Automation']
        detail.write_row(0,0,headers,heading); detail.freeze_panes(1,3); detail.set_column(0,1,20); detail.set_column(2,8,48); detail.set_column(9,15,24)
        rows=[]
        for i,c in enumerate(self.cases,1):
            row_values=[c['id'],c['category'],c['name'],c['name'],'Isolated CI fixture, recorded source',
                'Run the linked named assertion in tool/qa or source test',c['name'],'Assertion succeeds',
                c['detail'] or 'Observed assertions passed',c['status'],'P2','Requires triage on failure',
                c['duration_ms'],result['run_url'],self.metrics.get('scope','See raw logs'),'Automated']
            detail.write_row(i,0,row_values,wrap); detail.set_row(i,48); rows.append(row_values)
        detail.autofilter(0,0,len(rows),15); book.close()
        with (self.out/'test-cases.csv').open('w',newline='',encoding='utf-8') as f:
            writer=csv.writer(f); writer.writerow(headers); writer.writerows(rows)
        body=''.join('<tr>'+''.join('<td>'+html.escape(str(v))+'</td>' for v in row)+'</tr>' for row in rows)
        (self.out/'report.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>VITALIS '+self.suite+' results</title><h1>'+self.suite+' '+status+'</h1><a href="report.xlsx" download>Download Excel</a><table><thead><tr>'+''.join('<th>'+h+'</th>' for h in headers)+'</tr></thead><tbody>'+body+'</tbody></table></html>',encoding='utf-8')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'],'a',encoding='utf-8') as f: f.write(f"## {self.suite}: {status}\n\n{executed} executed; {counts}. Minimum {self.minimum_cases}.\n\nDownload the Excel, CSV, HTML, JSON and raw evidence from Artifacts.\n\n{self.metrics.get('scope','')}\n")
        return 0 if status=='PASS' else 1

def require(condition,message):
    if not condition: raise AssertionError(message)
