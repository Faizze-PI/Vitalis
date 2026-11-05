"""Retain prerequisite holds; never overwrite an executed report."""
import os
from common import POLICY,Report
for suite in os.environ['PERF_SUITES'].split(','):
    report=Report(suite,minimum_cases=POLICY['cases'])
    if (report.out/'results.json').exists(): continue
    for i in range(POLICY['cases']): report.blocked(f'{suite} case {i+1}','Prerequisite/tooling failure; inspect GitHub job logs')
    report.write()
