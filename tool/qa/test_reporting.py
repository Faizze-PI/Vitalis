import importlib.util,json,os,shutil,tempfile,unittest
from pathlib import Path
import report as module
class ReportIntegrity(unittest.TestCase):
    def setUp(self):
        self.temp=Path(tempfile.mkdtemp(prefix='vitalis-qa-report-'))
        self.old=module.ROOT; module.ROOT=self.temp
        self.summary=os.environ.pop('GITHUB_STEP_SUMMARY',None)
    def tearDown(self):
        module.ROOT=self.old; shutil.rmtree(self.temp)
        if self.summary is not None: os.environ['GITHUB_STEP_SUMMARY']=self.summary
    def make(self,count,failed=False):
        report=module.Report('fixture')
        report.cases=[dict(id=str(i),category='Integrity',name='=untrusted text',status='FAIL' if failed and i==0 else 'PASS',duration_ms=1,detail='') for i in range(count)]
        return report
    def test_incomplete_run_cannot_pass(self): self.assertEqual(self.make(299).write(),1)
    def test_complete_executed_run_can_pass(self):
        r=self.make(300); self.assertEqual(r.write(),0)
        self.assertEqual(len(json.loads((r.out/'results.json').read_text())['cases']),300)
    def test_one_failure_cannot_be_hidden(self): self.assertEqual(self.make(300,True).write(),1)
    def test_bas_retains_completed_cases_when_catalogue_is_incomplete(self):
        from types import SimpleNamespace
        from unittest.mock import patch
        import sys
        import run as runner
        sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'reporting'))
        import core_report
        events=[{'type':'suite','suite':{'id':0,'path':str(runner.ROOT/'test/services/model_downloader_test.dart')}},
                {'type':'testStart','test':{'id':1,'name':'reject unsafe path','suiteID':0},'time':0},
                {'type':'testDone','testID':1,'result':'success','time':1},
                {'type':'done','success':True,'time':2}]
        result=SimpleNamespace(returncode=0,stdout='\n'.join(json.dumps(e) for e in events),stderr='')
        report=module.Report('bas')
        with patch.object(runner.subprocess,'run',return_value=result),patch.object(core_report,'write_core_report',return_value=False):
            with self.assertRaises(AssertionError): runner.bas(report)
        self.assertEqual(len(report.cases),1)
        self.assertEqual(report.cases[0]['status'],'PASS')
    def test_history_fixture_rejects_personal_devices(self):
        from history_fixture import validate_environment
        for args in [('472fa620','true','0'),('emulator-5554','','1'),('emulator-5554','true','0')]:
            with self.assertRaises(AssertionError): validate_environment(*args)
        validate_environment('emulator-5554','true','1')
        validate_environment('127.0.0.1:5555','true','','redroid','123','123')
        for args in [('127.0.0.1:5555','true','','redroid','other','123'),
                     ('472fa620','true','','redroid','123','123')]:
            with self.assertRaises(AssertionError): validate_environment(*args)
    def test_appium_http_metrics_count_actual_logs(self):
        from mobile import appium_http_metrics
        text='[HTTP] --> GET /status\n[HTTP] <-- GET /status 200 10 ms - 2\n[HTTP] --> POST /session/x/element\n[HTTP] <-- POST /session/x/element 404 25 ms - 40\n[HTTP] --> GET /pending\n'
        text=text.replace('[HTTP]','\x1b[38;5;86m[HTTP]\x1b[0m')
        metrics=appium_http_metrics(text)
        self.assertEqual(metrics['driver_http_requests'],3)
        self.assertEqual(metrics['driver_http_responses'],2)
        self.assertEqual(metrics['driver_http_error_responses'],1)
        self.assertEqual(metrics['driver_http_median_ms'],17.5)
        self.assertNotIn('driver_http_median_ms',appium_http_metrics('no HTTP traffic'))
    def test_navigation_selector_rejects_content_and_back_buttons(self):
        import re
        from mobile import tab_description_pattern
        for label in ['Chats','Models','Saved','Settings']:
            pattern=tab_description_pattern(label)
            self.assertTrue(re.fullmatch(pattern,label))
            self.assertTrue(re.fullmatch(pattern,label+'\nTab 1 of 4'))
            for other in ['Back to '+label,label+' chats are available', 'Open '+label]:
                self.assertIsNone(re.fullmatch(pattern,other))
    def test_bundle_remains_downloadable_when_suites_fail(self):
        import subprocess,sys
        root=self.temp/'qa-bundle'; root.mkdir()
        source=Path(__file__).resolve().parent/'bundle.py'
        env={**os.environ,'QA_JOB_RESULTS':json.dumps({s:{'result':'failure'} for s in ['selenium','appium','bas','dast','load']}),'GITHUB_STEP_SUMMARY':str(self.temp/'summary.md')}
        result=subprocess.run([sys.executable,str(source)],cwd=self.temp,env=env)
        self.assertEqual(result.returncode,1)
        self.assertTrue((root/'FINAL_TEST_SUMMARY.xlsx').exists())
        self.assertFalse(root.name.startswith('.'))
    def test_minimum_has_five_independent_suite_gates(self):
        import yaml
        workflow=yaml.safe_load((Path(__file__).resolve().parents[2]/'.github/workflows/behaviour-qa.yml').read_text())
        self.assertTrue(set(['appium','selenium','bas','dast','load']).issubset(workflow['jobs']))
if __name__=='__main__': unittest.main()
