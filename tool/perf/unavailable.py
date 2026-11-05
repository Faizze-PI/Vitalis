"""Retain prerequisite holds; never overwrite an executed report."""
import os
from common import case_count,Report
for suite in os.environ['PERF_SUITES'].split(','):
    report=Report(suite,minimum_cases=case_count(suite))
    if (report.out/'results.json').exists(): continue
    for i in range(case_count(suite)): report.blocked(f'{suite} case {i+1}','Prerequisite/tooling failure; inspect GitHub job logs')
    report.write()
