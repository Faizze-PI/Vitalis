import json, math, os, re, statistics, subprocess, time
from urllib.parse import quote
from report import require
PACKAGE='com.vitalis.vitalis_app'
def tab_description_pattern(label):
    require(label in ['Chats','Models','Saved','Settings'],'Unknown navigation destination')
    return '(?s)^'+re.escape(label)+r'(?:\n.*)?$'

def find_navigation_element(driver,label):
    pattern=tab_description_pattern(label)
    selector='new UiSelector().descriptionStartsWith('+json.dumps(label)+').clickable(true)'
    for element in driver.find_elements('-android uiautomator',selector):
        if re.fullmatch(pattern,element.get_attribute('contentDescription') or ''):
            return element
    return False

def adb(*args,check=True):
    r=subprocess.run(['adb',*args],text=True,capture_output=True,timeout=45)
    if check: require(r.returncode==0,r.stdout+r.stderr)
    return r.stdout+r.stderr

def run(report):
    from appium import webdriver
    from appium.options.android import UiAutomator2Options
    from selenium.webdriver.support.ui import WebDriverWait
    options=UiAutomator2Options().load_capabilities({'platformName':'Android','appium:automationName':'UiAutomator2',
        'appium:udid':os.environ.get('ANDROID_SERIAL','emulator-5554'),'appium:appPackage':PACKAGE,
        'appium:appActivity':'.MainActivity','appium:noReset':True,'appium:forceAppLaunch':True,
        'appium:newCommandTimeout':120,'appium:adbExecTimeout':60000,'appium:appWaitDuration':90000})
    driver=webdriver.Remote('http://127.0.0.1:4723',options=options)
    def tab(label):
        WebDriverWait(driver,90).until(lambda d:find_navigation_element(d,label)).click()
        markers={'Chats':'New Chat','Models':'Model Library','Saved':'Reusable context for your conversations','Settings':'Appearance'}
        WebDriverWait(driver,30).until(lambda d:markers[label] in d.page_source)
        require(driver.current_package==PACKAGE,'App left foreground')
    try:
        from history_fixture import seed
        def prepare():
            WebDriverWait(driver,90).until(lambda d:'Open Model Library' in d.page_source)
            driver.save_screenshot(str(report.out/'fresh-model-setup.png'))
            (report.out/'fresh-model-setup.xml').write_text(driver.page_source,encoding='utf-8')
            seed(report)
            driver.activate_app(PACKAGE)
            tab('Settings')
        report.case('Fresh model setup then saved-history fixture reaches navigation',prepare,'Startup prerequisites')
        require(report.cases[-1]['status']=='PASS','Startup gate failed; dependent UI scenarios cannot execute')
        if report.suite=='appium':
            for font in [.85,1.0,1.15,1.3,1.5]:
                adb('shell','settings','put','system','font_scale',str(font))
                for rotation,lifecycle in [(0,'warm'),(1,'warm'),(0,'background'),(1,'background'),(0,'restart')]:
                    adb('shell','settings','put','system','accelerometer_rotation','0')
                    adb('shell','settings','put','system','user_rotation',str(rotation))
                    for source in ['Chats','Models','Saved','Settings']:
                        for target in ['Chats','Models','Saved','Settings']:
                            if source==target: continue
                            def transition(source=source,target=target,lifecycle=lifecycle):
                                tab(source)
                                if lifecycle=='background': driver.background_app(1)
                                if lifecycle=='restart': driver.terminate_app(PACKAGE); driver.activate_app(PACKAGE)
                                tab(target)
                            report.case(f'{source} to {target}; font={font}; rotation={rotation}; {lifecycle}',transition,'Navigation compatibility')
                            require(sum(c['status']=='FAIL' for c in report.cases)<3,'Three failures; stop invalid dependent navigation and retain incomplete suite')
            report.metrics['scope']='300 navigation scenarios: 12 transitions x 5 font scales x 5 orientation/lifecycle conditions. This does not claim complete feature or inference coverage.'
        else:
            for i in range(300):
                label=['Saved','Settings','Chats','Models'][i%4]
                report.case(f'Sequential action {i+1}: {label}',lambda label=label:tab(label),'UI workload samples')
                require(sum(c['status']=='FAIL' for c in report.cases)<3,'Repeated workload failures; retain incomplete suite')
            times=[c['duration_ms'] for c in report.cases[1:]]
            report.metrics.update(median_action_ms=statistics.median(times),p95_action_ms=sorted(times)[int(.95*(len(times)-1))],
                widget_actions=300,scope='300 sequential UI workload samples; not 300 unique features, concurrent users, model TTFT or translated-device performance ratification.')
        driver.save_screenshot(str(report.out/'final-screen.png'))
        (report.out/'hierarchy.xml').write_text(driver.page_source,encoding='utf-8')
    finally:
        try:
            driver.save_screenshot(str(report.out/'last-visible-screen.png'))
            (report.out/'last-hierarchy.xml').write_text(driver.page_source,encoding='utf-8')
            (report.out/'complete-emulator-logcat.log').write_text(adb('logcat','-d'),encoding='utf-8')
        except Exception as capture_error:
            (report.out/'capture-error.txt').write_text(str(capture_error),encoding='utf-8')
        driver.quit()

def dast(report):
    for component in ['.transfer.TransferJobService','androidx.work.impl.foreground.SystemForegroundService']:
        def probe(component=component):
            text=adb('shell','am','startservice','-n',PACKAGE+'/'+component,check=False)
            (report.out/(component.split('.')[-1]+'.log')).write_text(text,encoding='utf-8')
            require('not exported' in text.lower() or 'permission denial' in text.lower(),'Private component access not denied: '+text)
        report.case('Private service '+component,probe,'Component isolation')
    payloads=['../private','../../databases','%2e%2e/files','%00','../models','C:/private','/absolute/path','a'*128,'unicode-test','\\private']
    for scheme in ['file','content','https','http','vitalis','data','javascript','ftp','intent','unknown']:
        for index,payload in enumerate(payloads):
            value=scheme+'://qa.invalid/'+quote(payload,safe='')
            for action in ['VIEW','SEND','EDIT']:
                def probe(value=value,action=action):
                    output=adb('shell','am','start','-W','-n',PACKAGE+'/.MainActivity','-a','android.intent.action.'+action,'-d',value)
                    require('Error:' not in output,'Intent failed before app')
                    require(adb('shell','pidof',PACKAGE).strip(),'App lost after external intent')
                report.case(f'{action}; scheme={scheme}; payload={index}',probe,'External intent fuzz')
    report.case('Private files inaccessible to shell',lambda:require('permission denied' in adb('shell','ls','/data/user/0/'+PACKAGE+'/files',check=False).lower(),'Private files accessible'),'File isolation')
    report.metrics['scope']='300 external-intent fuzz scenarios (10 schemes x 10 payload classes x 3 actions), plus isolation probes. Non-crashing ingress alone is not proof of security.'

def appium_http_metrics(text):
    text=re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", text)
    requests=re.findall(r'\[HTTP\] --> (?:GET|POST|DELETE|PUT|PATCH|OPTIONS|HEAD) ',text)
    responses=re.findall(r'\[HTTP\] <-- (?:GET|POST|DELETE|PUT|PATCH|OPTIONS|HEAD) \S+ (\d{3}) ([\d.]+) ms',text)
    metrics=dict(driver_http_requests=len(requests),driver_http_responses=len(responses),
                 driver_http_error_responses=sum(int(status)>=400 for status,_ in responses))
    if responses:
        times=sorted(float(duration) for _,duration in responses)
        metrics.update(driver_http_median_ms=statistics.median(times),
                       driver_http_p95_ms=times[min(len(times)-1,math.ceil(.95*len(times))-1)])
    return metrics

def logs(report):
    driver_log=report.out/'appium.log'
    if driver_log.exists():
        report.metrics.update(appium_http_metrics(driver_log.read_text(errors='replace')))
        report.metrics['request_log_scope']='Local Appium driver HTTP traffic, not model token rate or Hub load'
    crash=adb('logcat','-d','-b','crash'); (report.out/'crash.log').write_text(crash,encoding='utf-8')
    report.case('No attributable fatal crash',lambda:require(PACKAGE not in crash,'Inspect crash.log'),'Crash audit')
    source=report.out.parents[1]/'.qa-apk'/'source.txt'
    if source.exists(): report.metrics['apk_source']=source.read_text().strip()
    pid=adb('shell','pidof',PACKAGE).strip().split()[0]
    text=adb('logcat','-d','--pid='+pid); (report.out/'app.log').write_text(text,encoding='utf-8')
    report.metrics['captured_app_log_lines']=len(text.splitlines())
