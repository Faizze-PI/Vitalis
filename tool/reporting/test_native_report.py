import unittest

from native_report import make_native_report
from test_validation_report import events


class NativeReportTest(unittest.TestCase):
    def report(self, **changes):
        inputs = {'lifecycle': events(), 'fault': events().replace('real assertion', 'fault assertion')}
        inputs.update(changes)
        return make_native_report(inputs, '/repo', 'a' * 40, 'https://example.test/run')

    def test_each_real_runner_is_counted_without_storage_measurements(self):
        report = self.report()
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['test_count'], 2)
        self.assertEqual(report['counts']['PASS'], 2)
        self.assertIsNone(report['runner_elapsed_ms'])
        self.assertEqual(report['measurements'], [])

    def test_missing_fault_runner_blocks_acceptance(self):
        self.assertEqual(self.report(fault='')['status'], 'FAIL')

    def test_missing_terminal_blocks_acceptance(self):
        self.assertEqual(self.report(lifecycle='\n'.join(events().splitlines()[:-1]))['status'], 'FAIL')

    def test_duplicate_cases_cannot_inflate_totals(self):
        self.assertEqual(self.report(fault=events())['status'], 'FAIL')

    def test_failed_assertion_is_preserved(self):
        report = self.report(fault=events().replace('real assertion', 'fault assertion')
                             .replace('"result": "success"', '"result": "failure"'))
        self.assertEqual(report['counts']['FAIL'], 1)
        self.assertEqual(report['status'], 'FAIL')

    def test_invalid_source_cannot_pass(self):
        report = make_native_report({'lifecycle': events(), 'fault': events()}, '/repo', 'unknown', 'local')
        self.assertEqual(report['status'], 'FAIL')


if __name__ == '__main__':
    unittest.main()
