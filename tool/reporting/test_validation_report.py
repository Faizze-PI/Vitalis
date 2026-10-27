import json
import unittest

from validation_report import csv_safe, make_report


def events(extra=None):
    rows = [
        {'type': 'suite', 'suite': {'id': 1, 'path': '/repo/test/example_test.dart'}},
        {'type': 'testStart', 'test': {'id': 2, 'name': 'real assertion', 'suiteID': 1}, 'time': 10},
        {'type': 'testDone', 'testID': 2, 'hidden': False, 'result': 'success', 'skipped': False, 'time': 10},
        {'type': 'done', 'success': True, 'time': 11},
    ]
    if extra:
        rows.insert(-1, extra)
    return '\n'.join(json.dumps(row) for row in rows)


def metrics():
    return '\n'.join(json.dumps({'name': f'workload {index}', 'operations': 1, 'errors': 0,
        'elapsed_micros': 1000, 'operations_per_second': 1000, 'min_micros': 0,
        'mean_micros': 0, 'median_micros': 0, 'p95_micros': 0, 'max_micros': 0}) for index in range(3))


class ReportTest(unittest.TestCase):
    def report(self, raw=None, measured=None):
        return make_report(events() if raw is None else raw,
                           metrics() if measured is None else measured,
                           '/repo', 'a'*40, 'https://github.com/example/repo/actions/runs/1')

    def test_real_zero_duration_is_retained(self):
        report = self.report()
        self.assertEqual(report['status'], 'PASS')
        self.assertEqual(report['test_count'], 1)
        self.assertEqual(report['cases'][0]['duration_ms'], 0)

    def test_missing_terminal_cannot_pass(self):
        self.assertEqual(self.report('\n'.join(events().splitlines()[:-1]))['status'], 'FAIL')

    def test_failed_case_cannot_pass(self):
        self.assertEqual(self.report(events().replace('"result": "success"', '"result": "failure"'))['counts']['FAIL'], 1)

    def test_skip_cannot_pass(self):
        self.assertEqual(self.report(events().replace('"skipped": false', '"skipped": true'))['status'], 'FAIL')

    def test_duplicate_completion_cannot_inflate_count(self):
        extra = {'type':'testDone','testID':2,'result':'success','hidden':False,'time':10}
        report = self.report(events(extra))
        self.assertEqual(report['test_count'], 1)
        self.assertEqual(report['status'], 'FAIL')

    def test_missing_event_fields_preserve_prior_cases_and_fail(self):
        report = self.report(events({'type':'testDone'}))
        self.assertEqual(report['test_count'], 1)
        self.assertEqual(report['status'], 'FAIL')

    def test_fixture_failure_is_not_hidden(self):
        extra = {'type':'testDone','testID':7,'result':'failure','hidden':True,'time':10}
        self.assertEqual(self.report(events(extra))['status'], 'FAIL')

    def test_malformed_json_is_not_ignored(self):
        self.assertEqual(self.report(events()+'\n{"broken"')['status'], 'FAIL')

    def test_missing_metrics_is_not_zero(self):
        report = self.report(measured='')
        self.assertEqual(report['status'], 'FAIL')
        self.assertEqual(report['measurements'], [])

    def test_nonfinite_metrics_rejected(self):
        self.assertEqual(self.report(measured=metrics().replace('1000', 'NaN'))['status'], 'FAIL')

    def test_inconsistent_rate_rejected(self):
        self.assertEqual(self.report(measured=metrics().replace('"operations_per_second": 1000', '"operations_per_second": 4'))['status'], 'FAIL')

    def test_measured_errors_fail_gate(self):
        self.assertEqual(self.report(measured=metrics().replace('"errors": 0', '"errors": 1'))['status'], 'FAIL')

    def test_missing_source_cannot_pass(self):
        report = make_report(events(), metrics(), '/repo', 'unknown', 'https://github.com/example/repo/actions/runs/1')
        self.assertEqual(report['status'], 'FAIL')

    def test_fractional_operation_count_rejected(self):
        bad = metrics().replace('"operations": 1', '"operations": 1.5').replace('"operations_per_second": 1000', '"operations_per_second": 1500')
        self.assertEqual(self.report(measured=bad)['status'], 'FAIL')

    def test_source_outside_checkout_rejected(self):
        self.assertEqual(self.report(events().replace('/repo/test/', '/elsewhere/test/'))['status'], 'FAIL')

    def test_csv_formula_injection_is_literal(self):
        for text in ('=1+1', '+SUM(A1:A2)', '-1+2', '@formula'):
            self.assertEqual(csv_safe(text), "'"+text)
        self.assertEqual(csv_safe(0), 0)


if __name__ == '__main__':
    unittest.main()
