"""CI-only reports from real Flutter machine events. Never fabricates results."""
import argparse
import csv
import html
import json
import math
import re
from pathlib import Path


def parse_events(text, root):
    starts, suites, completed, cases, problems = {}, {}, set(), [], []
    terminal = None
    prefix = str(root).replace('\\', '/').rstrip('/') + '/'
    for line in text.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            if line.lstrip().startswith('{'):
                problems.append('Malformed runner event')
            continue
        if not isinstance(event, dict):
            continue
        kind = event.get('type')
        required = {'suite': ('suite',), 'testStart': ('test', 'time'),
                    'testDone': ('testID', 'result', 'time'), 'done': ('success', 'time')}
        if kind in required and any(key not in event for key in required[kind]):
            problems.append('Malformed runner event structure')
            continue
        if kind in ('testStart', 'testDone', 'done') and (
                type(event['time']) is not int or event['time'] < 0):
            problems.append('Invalid runner clock')
            continue
        payload = event.get('suite') if kind == 'suite' else event.get('test')
        if kind in ('suite', 'testStart'):
            keys = ('id', 'path') if kind == 'suite' else ('id', 'name', 'suiteID')
            if (not isinstance(payload, dict) or any(key not in payload for key in keys)
                    or type(payload['id']) is not int
                    or not isinstance(payload['path' if kind == 'suite' else 'name'], str)
                    or (kind == 'testStart' and type(payload['suiteID']) is not int)):
                problems.append('Malformed test or suite identity')
                continue
        if kind == 'testDone' and type(event['testID']) is not int:
            problems.append('Invalid completion identity')
            continue
        if kind == 'suite':
            suite = event['suite']
            suites[suite['id']] = suite['path'].replace('\\', '/')
        elif kind == 'testStart':
            test = event['test']
            if test['id'] in starts:
                problems.append('Duplicate test start')
            starts[test['id']] = (test, event['time'])
        elif kind == 'error':
            problems.append(f"Runner error for test {event.get('testID', 'setup')}")
        elif kind == 'testDone':
            identity = event['testID']
            if identity in completed or identity not in starts:
                problems.append('Duplicate or unmatched test completion')
                continue
            completed.add(identity)
            if event.get('hidden'):
                if event.get('result') != 'success':
                    problems.append('Loading or fixture setup failed')
                continue
            test, began = starts[identity]
            duration = event['time'] - began
            if duration < 0:
                problems.append('Negative runner duration')
            path = suites.get(test['suiteID'], '')
            if not path.startswith(prefix):
                problems.append('Test source is outside the checkout')
                path = 'unresolved source'
            else:
                path = path[len(prefix):]
            status = ('SKIP' if event.get('skipped') else
                      'PASS' if event['result'] == 'success' else 'FAIL')
            cases.append({'id': len(cases) + 1, 'file': path,
                          'name': test['name'], 'status': status,
                          'duration_ms': duration})
        elif kind == 'done':
            if terminal is not None:
                problems.append('Duplicate terminal runner event')
            terminal = event
    if terminal is None or terminal.get('success') is not True:
        problems.append('Runner did not finish successfully')
    if set(starts) != completed:
        problems.append('Unfinished test or setup operation')
    if not cases:
        problems.append('No test cases completed')
    return cases, problems, terminal


def parse_metrics(text):
    records, problems, names = [], [], set()
    numeric = ('operations', 'errors', 'elapsed_micros', 'operations_per_second',
               'min_micros', 'mean_micros', 'median_micros', 'p95_micros', 'max_micros')
    for line in text.splitlines():
        if not line.strip():
            continue
        try:
            value = json.loads(line)
            if (not isinstance(value, dict) or
                    any(isinstance(value[key], bool) or not isinstance(value[key], (int, float))
                        or not math.isfinite(value[key]) or value[key] < 0 for key in numeric)):
                raise ValueError('Invalid measurement')
            if (any(type(value[key]) is not int for key in ('operations', 'errors', 'elapsed_micros'))
                    or value['operations'] <= 0 or value['elapsed_micros'] <= 0 or value['name'] in names):
                raise ValueError('Invalid measurement identity or denominator')
            expected_rate = value['operations'] * 1000000 / value['elapsed_micros']
            if not math.isclose(value['operations_per_second'], expected_rate, rel_tol=1e-9):
                raise ValueError('Rate disagrees with count and elapsed time')
            if not (value['min_micros'] <= value['median_micros'] <= value['p95_micros'] <= value['max_micros']
                    and value['min_micros'] <= value['mean_micros'] <= value['max_micros']):
                raise ValueError('Inconsistent measurement bounds')
            names.add(value['name'])
            records.append(value)
            if value['errors']:
                problems.append('Storage workload reported errors')
        except (ValueError, TypeError, KeyError):
            problems.append('Malformed or inconsistent measurement')
    if len(records) != 3:
        problems.append('All three storage measurements are required')
    return records, problems


def csv_safe(value):
    if isinstance(value, str) and value.startswith(('=', '+', '-', '@')):
        return "'" + value
    return value


def make_report(events, metrics, root, source, run_url):
    cases, problems, terminal = parse_events(events, root)
    measurements, metric_problems = parse_metrics(metrics)
    problems.extend(metric_problems)
    if not re.fullmatch(r'[a-f0-9]{40}', source):
        problems.append('Missing or invalid source commit identity')
    counts = {name: sum(case['status'] == name for case in cases) for name in ('PASS', 'FAIL', 'SKIP')}
    status = 'PASS' if not problems and not counts['FAIL'] and not counts['SKIP'] else 'FAIL'
    return {'source': source, 'run_url': run_url, 'status': status,
            'counts': counts, 'test_count': len(cases), 'cases': cases,
            'runner_elapsed_ms': terminal.get('time') if terminal else None,
            'measurements': measurements, 'problems': problems,
            'scope': 'Hosted Flutter tests and host SQLite measurements; not phone E2E or inference performance'}


def write_reports(report, output):
    # GitHub runners do not have Codex's bundled artifact authoring runtime.
    # Use the hash-pinned CI-only writer; it never becomes an app dependency.
    import xlsxwriter
    output.mkdir(parents=True, exist_ok=True)
    (output/'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    with (output/'test-cases.csv').open('w', newline='', encoding='utf-8-sig') as stream:
        writer = csv.writer(stream)
        writer.writerow(['ID', 'File', 'Test case', 'Result', 'Test duration (ms)'])
        writer.writerows([[csv_safe(row[key]) for key in ('id', 'file', 'name', 'status', 'duration_ms')]
                          for row in report['cases']])
    workbook = xlsxwriter.Workbook(str(output/'VITALIS-Test-Results.xlsx'),
                                  {'strings_to_formulas': False, 'strings_to_urls': False})
    normal = workbook.add_format({'font_name': 'Arial', 'font_size': 10, 'valign': 'vcenter'})
    wrapped = workbook.add_format({'font_name': 'Arial', 'font_size': 10, 'text_wrap': True, 'valign': 'vcenter', 'align': 'left'})
    title = workbook.add_format({'font_name': 'Arial', 'font_size': 14, 'bold': True, 'font_color': '#183B56'})
    heading = workbook.add_format({'font_name': 'Arial', 'font_size': 10, 'bold': True,
                                   'bg_color': '#183B56', 'font_color': 'white', 'text_wrap': True,
                                   'align': 'center', 'valign': 'vcenter'})
    decimal = workbook.add_format({'font_name': 'Arial', 'font_size': 10, 'num_format': '0.000', 'valign': 'vcenter'})
    summary, details, measurements = [workbook.add_worksheet(name) for name in ('Summary', 'Test cases', 'Measurements')]
    for sheet in (summary, details, measurements):
        sheet.hide_gridlines(2)
        sheet.set_default_row(24)
    summary.set_column('A:A', 30, normal); summary.set_column('B:B', 95, wrapped)
    summary.write('A2', 'VITALIS Actions test results', title)
    values = [('Overall result', report['status']), ('Passed', report['counts']['PASS']),
              ('Failed', report['counts']['FAIL']), ('Skipped', report['counts']['SKIP']),
              ('App/test source', report['source']), ('Actions run', report['run_url']),
              ('Scope', report['scope']), ('Timing', 'Runner durations are real; zero milliseconds is valid at runner resolution.'),
              ('Phone/emulator gates', 'Not executed by this hosted job; physical and arm64 instrumentation remain separate.')]
    values += [('Execution problem', problem) for problem in report['problems']]
    for index, row in enumerate(values, 4):
        summary.write_row(index, 0, row)
        summary.set_row(index, 38)
    details.write('A2', 'Executed test cases', title)
    headers = ['ID', 'Source file', 'Test case', 'Result', 'Test duration (ms)']
    details.write_row('A5', headers, heading)
    details.set_column('A:A', 9, normal); details.set_column('B:B', 68, wrapped)
    details.set_column('C:C', 100, wrapped); details.set_column('D:E', 20, normal)
    for index, case in enumerate(report['cases'], 5):
        details.write_row(index, 0, [case[key] for key in ('id', 'file', 'name', 'status', 'duration_ms')])
        details.set_row(index, 45)
    details.autofilter(4, 0, max(4, len(report['cases'])+4), 4)
    details.freeze_panes(5, 2)
    measurements.write('A2', 'Host storage measurements', title)
    measurements.write('A3', 'Not model TTFT, phone latency or 100 app users.', normal)
    measurements.write_row('A5', ['Workload', 'Operations', 'Errors', 'Elapsed (s)', 'Operations/s',
                                       'Min (ms)', 'Mean (ms)', 'Median (ms)', 'P95 (ms)', 'Max (ms)'], heading)
    measurements.set_column('A:A', 70, wrapped); measurements.set_column('B:C', 14, normal)
    measurements.set_column('D:J', 17, decimal)
    for index, metric in enumerate(report['measurements'], 5):
        values = [metric['name'], metric['operations'], metric['errors'], metric['elapsed_micros']/1e6,
                  metric['operations_per_second']] + [metric[key]/1000 for key in
                  ('min_micros', 'mean_micros', 'median_micros', 'p95_micros', 'max_micros')]
        measurements.write_row(index, 0, values); measurements.set_row(index, 52)
    measurements.freeze_panes(5, 1)
    workbook.close()
    rows = ''.join('<tr>' + ''.join(f'<td>{html.escape(str(case[key]))}</td>' for key in
                   ('id', 'file', 'name', 'status', 'duration_ms')) + '</tr>' for case in report['cases'])
    (output/'report.html').write_text('<!doctype html><html lang="en"><meta charset="utf-8"><title>VITALIS test results</title>'
        '<style>body{font:15px system-ui;margin:32px;color:#183b56}table{border-collapse:collapse;width:100%}'
        'th,td{padding:8px;text-align:left;border-bottom:1px solid #ddd}th{background:#183b56;color:white}</style>'
        f'<h1>VITALIS test results: {report["status"]}</h1><p>{html.escape(report["scope"])}</p>'
        f'<p>{html.escape(str(report["counts"]))}</p><table><thead><tr><th>ID</th><th>File</th><th>Case</th><th>Result</th><th>Test ms</th></tr></thead><tbody>'
        + rows + '</tbody></table></html>', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--source', required=True)
    parser.add_argument('--run-url', required=True)
    args = parser.parse_args()
    directory = Path(args.directory)
    def read(name):
        path = directory/name
        return path.read_text(encoding='utf-8-sig') if path.exists() else ''
    report = make_report(read('machine.log'), read('metrics.jsonl'), args.root, args.source, args.run_url)
    write_reports(report, directory)
    from core_report import write_core_report
    core_passed = write_core_report(report, directory)
    print(json.dumps({'status': report['status'], 'tests': report['test_count'], 'counts': report['counts']}))
    import os
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a', encoding='utf-8') as stream:
            stream.write(f"## VITALIS validation: {report['status']}\n\nPassed: {report['counts']['PASS']}; failed: {report['counts']['FAIL']}; skipped: {report['counts']['SKIP']}.\n\nDownload **VITALIS-Excel-test-report-Windows** in this run's Artifacts section for Excel, CSV, HTML and raw measurements.\n\n{report['scope']}\n")
    return 0 if report['status'] == 'PASS' and core_passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
