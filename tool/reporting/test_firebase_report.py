import unittest

from firebase_report import parse_junit


class FirebaseReportTests(unittest.TestCase):
    def test_reports_actual_outcomes_and_duration(self):
        xml = b'''<testsuites><testsuite tests="3" failures="1" errors="0" skipped="1">
          <testcase classname="example.Test" name="ok" time="0.2" />
          <testcase classname="example.Test" name="bad" time="1.5"><failure message="broken" /></testcase>
          <testcase classname="example.Test" name="later"><skipped /></testcase>
        </testsuite></testsuites>'''
        cases = parse_junit(xml, '28')
        self.assertEqual([case['status'] for case in cases], ['PASS', 'FAIL', 'SKIPPED'])
        self.assertEqual(cases[1]['detail'], 'broken')
        self.assertEqual(cases[0]['seconds'], 0.2)

    def test_rejects_discrepant_suite_counts(self):
        xml = b'<testsuites><testsuite tests="2" failures="0" errors="0" skipped="0"><testcase name="only"/></testsuite></testsuites>'
        with self.assertRaises(ValueError):
            parse_junit(xml, '35')

    def test_rejects_invalid_xml_and_empty_suite(self):
        for xml in (b'<broken', b'<testsuites/>'):
            with self.assertRaises(ValueError):
                parse_junit(xml, '28')


if __name__ == '__main__':
    unittest.main()
