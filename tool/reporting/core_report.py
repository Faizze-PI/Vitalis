"""Stable 300-case view; never substitutes catalogue statuses for execution."""
import json
from collections import Counter
from pathlib import Path


def core_rows(report, catalogue):
    keys = [(row['file'], row['name']) for row in catalogue]
    if len(keys) != 300 or len(set(keys)) != 300 or len({r['id'] for r in catalogue}) != 300:
        raise ValueError('Core catalogue requires 300 unique identities')
    actual = {}
    for case in report['cases']:
        key = (case['file'], case['name'])
        if key in actual:
            raise ValueError('Ambiguous executed test identity')
        actual[key] = case
    rows = []
    for case in catalogue:
        result = actual.get((case['file'], case['name']))
        rows.append({**case, 'status': result['status'] if result else 'BLOCKED',
                     'duration_ms': result['duration_ms'] if result else None,
                     'actual': ('Runner completed the assertion case: ' + result['status']) if result else 'No matching completion event in this run',
                     'evidence': report['run_url'],
                     'remarks': 'Host evidence only; not physical Android verification.'})
    return rows


def write_core_report(report, output):
    import xlsxwriter
    catalogue = json.loads(Path(__file__).with_name('core_300_cases.json').read_text(encoding='utf-8'))
    rows = core_rows(report, catalogue)
    counts = Counter(row['status'] for row in rows)
    (output/'core-300-results.json').write_text(json.dumps({'source': report['source'], 'rows': rows}, indent=2), encoding='utf-8')
    book = xlsxwriter.Workbook(str(output/'VITALIS-Core-300-Test-Cases.xlsx'),
                              {'strings_to_formulas': False, 'strings_to_urls': False})
    heading = book.add_format({'bold': True, 'bg_color': '#183B56', 'font_color': 'white', 'text_wrap': True})
    wrap = book.add_format({'text_wrap': True, 'valign': 'top', 'font_name': 'Arial', 'font_size': 10})
    summary, detail = book.add_worksheet('SUMMARY'), book.add_worksheet('TEST RESULTS')
    summary.hide_gridlines(2); detail.hide_gridlines(2)
    summary.set_column('A:A', 28); summary.set_column('B:B', 110, wrap)
    values = [('VITALIS core programme', '300 distinct cases; full-suite report retained separately'),
              ('Total Tests', 300), ('Passed', counts['PASS']), ('Failed', counts['FAIL']),
              ('Skipped', counts['SKIP']), ('Blocked', counts['BLOCKED']),
              ('Pass Percentage', counts['PASS']/3), ('Build/Commit', report['source']),
              ('Environment', report['scope']), ('Evidence', report['run_url']),
              ('Readiness', 'HOST CASES PASS' if counts['PASS'] == 300 and report['status'] == 'PASS' else 'HOLD'),
              ('Execution Time', str(report['runner_elapsed_ms']) + ' ms for full runner; case durations are not additive wall time'),
              ('Detailed steps', 'Source tests are authoritative fixtures, actions and assertions; see each source/name pair.'),
              ('Severity', 'Failure impact requires triage; no invented severity or security score.')]
    for index, value in enumerate(values):
        summary.write_row(index, 0, value); summary.set_row(index, 34)
    headers = ['Test ID', 'Test Category', 'Test Name', 'Objective', 'Preconditions', 'Steps',
               'Expected Result', 'Actual Result', 'Status', 'Priority', 'Severity',
               'Execution Time (ms)', 'Screenshot/Artifact', 'Remarks', 'Automation Status', 'Source File']
    detail.write_row(0, 0, headers, heading); detail.set_row(0, 36)
    detail.set_column('A:B', 20, wrap); detail.set_column('C:H', 55, wrap)
    detail.set_column('I:L', 22, wrap); detail.set_column('M:P', 65, wrap)
    fields = ('id', 'category', 'name', 'objective', 'preconditions', 'steps', 'expected',
              'actual', 'status', 'priority', 'severity', 'duration_ms', 'evidence', 'remarks', 'automation', 'file')
    for index, row in enumerate(rows, 1):
        detail.write_row(index, 0, [row[key] for key in fields]); detail.set_row(index, 90)
    detail.autofilter(0, 0, 300, 15); detail.freeze_panes(1, 2)
    book.close()
    return counts['PASS'] == 300
