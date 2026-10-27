import json
import unittest
from pathlib import Path

from core_report import core_rows


class CoreReportTest(unittest.TestCase):
    def setUp(self):
        self.catalogue = json.loads(Path(__file__).with_name('core_300_cases.json').read_text())
        self.report = {'run_url': 'local retained evidence', 'cases': [
            {**row, 'status': 'PASS', 'duration_ms': 0} for row in self.catalogue]}

    def test_three_hundred_distinct_real_cases(self):
        rows = core_rows(self.report, self.catalogue)
        self.assertEqual(len(rows), 300)
        self.assertTrue(all(r['status'] == 'PASS' for r in rows))
        self.assertEqual(rows[0]['duration_ms'], 0)

    def test_missing_case_is_blocked_not_passed(self):
        self.report['cases'].pop()
        self.assertEqual(core_rows(self.report, self.catalogue)[-1]['status'], 'BLOCKED')

    def test_failure_and_skip_preserved(self):
        self.report['cases'][0]['status'] = 'FAIL'
        self.report['cases'][1]['status'] = 'SKIP'
        self.assertEqual([r['status'] for r in core_rows(self.report, self.catalogue)[:2]], ['FAIL', 'SKIP'])

    def test_duplicate_catalogue_rejected(self):
        self.catalogue[-1] = self.catalogue[0]
        with self.assertRaises(ValueError):
            core_rows(self.report, self.catalogue)

    def test_ambiguous_execution_rejected(self):
        self.report['cases'].append(self.report['cases'][0])
        with self.assertRaises(ValueError):
            core_rows(self.report, self.catalogue)
