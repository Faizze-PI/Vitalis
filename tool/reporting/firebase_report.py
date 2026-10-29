"""Create a Firebase instrumentation report from retained JUnit XML."""

import argparse
import pathlib
import xml.etree.ElementTree as ET


def parse_junit(data, version):
    try:
        root = ET.fromstring(data)
    except ET.ParseError as error:
        raise ValueError('Malformed JUnit XML') from error
    suites = [root] if root.tag == 'testsuite' else root.findall('.//testsuite')
    if not suites:
        raise ValueError('No test suites in JUnit XML')
    cases = []
    for suite in suites:
        entries = suite.findall('testcase')
        counts = {'tests': len(entries), 'failures': 0, 'errors': 0, 'skipped': 0}
        for entry in entries:
            issue = next((entry.find(tag) for tag in ('failure', 'error', 'skipped')
                          if entry.find(tag) is not None), None)
            kind = issue.tag if issue is not None else None
            if kind:
                counts[{'failure': 'failures', 'error': 'errors', 'skipped': 'skipped'}[kind]] += 1
            cases.append({'api': version, 'class': entry.get('classname', ''),
                          'name': entry.get('name', ''),
                          'status': 'SKIPPED' if kind == 'skipped' else 'FAIL' if kind else 'PASS',
                          'seconds': float(entry.get('time', '0')),
                          'detail': (issue.get('message', '') or (issue.text or '').strip()) if issue is not None else ''})
        for key, value in counts.items():
            if key in suite.attrib and int(suite.attrib[key]) != value:
                raise ValueError(f'JUnit {key} count does not match cases')
    if not cases:
        raise ValueError('JUnit report has no cases')
    return cases


def main():
    import xlsxwriter

    parser = argparse.ArgumentParser()
    parser.add_argument('--api28', required=True)
    parser.add_argument('--api35', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--run-url', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    cases = []
    for version, path in [('28', args.api28), ('35', args.api35)]:
        cases.extend(parse_junit(pathlib.Path(path).read_bytes(), version))
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    with xlsxwriter.Workbook(output, {'strings_to_formulas': False, 'strings_to_urls': False}) as workbook:
        summary = workbook.add_worksheet('Summary')
        detail = workbook.add_worksheet('Test results')
        heading = workbook.add_format({'bold': True, 'bg_color': '#D9E5F5', 'border': 1})
        summary.set_column('A:A', 25)
        summary.set_column('B:F', 18)
        summary.write('A1', 'VITALIS Android instrumentation results', heading)
        summary.write('A2', 'Source commit'); summary.write('B2', args.source)
        summary.write('A3', 'Actions run'); summary.write('B3', args.run_url)
        summary.write_row('A5', ['Android API', 'Tests', 'Passed', 'Failed', 'Skipped', 'Result'], heading)
        for row, api in enumerate(('28', '35'), start=5):
            subset = [case for case in cases if case['api'] == api]
            count = lambda status: sum(case['status'] == status for case in subset)
            summary.write_row(row, 0, [api, len(subset), count('PASS'), count('FAIL'), count('SKIPPED'),
                                       'PASS' if count('FAIL') == 0 and count('SKIPPED') == 0 else 'REVIEW'])
        summary.write('A9', 'Scope: instrumentation tests only; not a complete app or physical-device qualification.')
        detail.set_column('A:A', 12); detail.set_column('B:B', 55); detail.set_column('C:C', 48)
        detail.set_column('D:E', 14); detail.set_column('F:F', 70)
        detail.freeze_panes(1, 0)
        detail.write_row(0, 0, ['Android API', 'Class', 'Test', 'Status', 'Seconds', 'Failure / skip detail'], heading)
        for row, case in enumerate(cases, start=1):
            detail.write_row(row, 0, [case[k] for k in ('api', 'class', 'name', 'status', 'seconds', 'detail')])
        detail.autofilter(0, 0, len(cases), 5)


if __name__ == '__main__':
    main()
