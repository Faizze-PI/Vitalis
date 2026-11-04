"""Environment diagnosis only: never a 300-case acceptance verdict."""
import json
from report import Report
from mobile import run
report=Report('appium')
error=None
try:
    run(report,navigation_only=True)
except Exception as failure:
    error=type(failure).__name__+': '+str(failure)
passed=error is None and len(report.cases)==5 and all(c['status']=='PASS' for c in report.cases)
(report.out/'navigation-environment-probe.json').write_text(json.dumps(dict(
    scope='Five environment/navigation checks only; not full suite acceptance',
    passed=passed,error=error,cases=report.cases),indent=2),encoding='utf-8')
raise SystemExit(0 if passed else 1)
