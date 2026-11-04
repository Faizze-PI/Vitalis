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
    def test_minimum_has_five_independent_suite_gates(self):
        import yaml
        workflow=yaml.safe_load((Path(__file__).resolve().parents[2]/'.github/workflows/behaviour-qa.yml').read_text())
        self.assertTrue(set(['appium','selenium','bas','dast','load']).issubset(workflow['jobs']))
if __name__=='__main__': unittest.main()
