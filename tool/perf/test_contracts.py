import tempfile,unittest
from pathlib import Path
from common import CATALOGUE,EvidenceUnavailable,frame_durations,regression_pairs,percentile
class PerformanceContracts(unittest.TestCase):
    def test_completed_suites_keep_fifty_and_remaining_have_twenty(self):
        self.assertEqual([c['name'] for c in CATALOGUE],['latency','throughput','stress','spike','endurance','startup','smoothness','resources','recovery','volume','concurrency','regression'])
        self.assertEqual(sum(c['minimum'] for c in CATALOGUE),360)
        self.assertEqual([c['minimum'] for c in CATALOGUE],[50]*4+[20]*8)
    def test_workflow_serializes_all_groups_and_preserves_case_minimums(self):
        import yaml
        jobs=yaml.safe_load((Path(__file__).resolve().parents[2]/'.github/workflows/performance-qa.yml').read_text())['jobs']
        chain=['prepare','android_latency','host_early','android_extended','host_late','regression']
        for before,after in zip(chain,chain[1:]): self.assertIn(before,jobs[after]['needs'])
        self.assertEqual(jobs['host_early']['env']['PERF_SUITES'],'throughput,stress,spike')
        self.assertEqual(jobs['android_extended']['env']['PERF_SUITES'],'endurance,startup,smoothness,resources,recovery')
        self.assertEqual(jobs['host_late']['env']['PERF_SUITES'],'volume,concurrency')
    def test_cpu_metadata_is_read_from_a_real_file_without_serials(self):
        from common import host_cpu_identity
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'cpuinfo'
            path.write_text('processor : 0\nCPU implementer : 0x41\nSerial : private\nprocessor : 1\nCPU implementer : 0x41\n')
            self.assertEqual(host_cpu_identity(path),['CPU implementer : 0x41'])
    def test_retained_passes_require_matching_run_and_actual_counts(self):
        from reuse import verify_report
        data={'suite':'latency','status':'PASS','source':'a'*40,'run_url':'https://github.com/Faizze-PI/Vitalis/actions/runs/123',
              'counts':{'PASS':50,'FAIL':0,'SKIP':0},'cases':[{'id':str(i),'status':'PASS'} for i in range(50)]}
        verify_report(data,'latency','123')
        with self.assertRaises(AssertionError):verify_report(data,'latency','456')
        data['cases'][0]['status']='FAIL'
        with self.assertRaises(AssertionError):verify_report(data,'latency','123')
    def test_frame_parser_rejects_unfinished_or_invalid_frames(self):
        raw='Flags,IntendedVsync,FrameCompleted\n0,1000000,18000000\n1,1000000,20000000\n0,1000000,9223372036854775807\n0,500,100\n'
        self.assertEqual(frame_durations(raw),[17.0])
        self.assertEqual(frame_durations('No frame samples'),[])
    def test_percentiles_are_nearest_rank_not_fabricated(self):
        self.assertEqual(percentile(range(1,51),.95),48)
    def fixture(self,source="candidate"):
        return dict(status='PASS',measurements=dict(apk_source=source,environment={'mode':'profile'},samples=[dict(name=str(i),measurements={'ui_ready_ms':100}) for i in range(50)]))
    def test_missing_baseline_is_unavailable_not_pass(self):
        with self.assertRaises(EvidenceUnavailable):regression_pairs(self.fixture(),None)
    def test_different_environments_cannot_be_compared(self):
        other=self.fixture();other['measurements']['environment']['mode']='debug'
        with self.assertRaises(EvidenceUnavailable):regression_pairs(self.fixture(),other)
    def test_incomplete_and_nonfinite_baselines_are_rejected(self):
        for value in [float('nan'),0,-1,float('inf')]:
            other=self.fixture();other['measurements']['samples'][0]['measurements']['ui_ready_ms']=value
            with self.assertRaises(EvidenceUnavailable):regression_pairs(self.fixture(),other)
    def test_same_apk_build_cannot_claim_cross_build_regression(self):
        with self.assertRaises(EvidenceUnavailable):regression_pairs(self.fixture(),self.fixture())
    def test_only_complete_matching_pairs_are_accepted(self):
        self.assertEqual(len(regression_pairs(self.fixture(),self.fixture('baseline'))),20)
if __name__=='__main__':unittest.main()
