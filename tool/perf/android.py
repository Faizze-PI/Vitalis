"""Profile-APK functional performance on owned native ARM Android only."""
import hashlib,json,os,re,subprocess,time,traceback
from common import ROOT,POLICY,Report,require,EvidenceUnavailable,frame_durations,percentile,host_cpu_identity,case_count
from mobile import PACKAGE,adb,find_navigation_element,appium_http_metrics
from history_fixture import seed,validate_environment
from appium import webdriver
from appium.options.android import UiAutomator2Options
from selenium.webdriver.support.ui import WebDriverWait

GROUPS={'latency':['latency'],'extended':['endurance','startup','resources','recovery']}
suites=GROUPS[os.environ['QA_PERFORMANCE_GROUP']]
log_file=ROOT/'.qa-results'/os.environ['QA_SUITE']/'appium.log'
driver=None;failed=False

def connect():
    options=UiAutomator2Options().load_capabilities({'platformName':'Android','appium:automationName':'UiAutomator2',
        'appium:udid':os.environ['ANDROID_SERIAL'],'appium:appPackage':PACKAGE,'appium:appActivity':'.MainActivity',
        'appium:noReset':True,'appium:forceAppLaunch':True,'appium:newCommandTimeout':180,'appium:adbExecTimeout':60000})
    return webdriver.Remote('http://127.0.0.1:4723',options=options)

def ready():
    WebDriverWait(driver,30).until(lambda d:find_navigation_element(d,'Chats'))
    require(driver.current_package==PACKAGE,'VITALIS is not foreground')

def tab(label):
    markers={'Chats':'New Chat','Models':'Model Library','Saved':'Reusable context for your conversations','Settings':'Appearance'}
    start=time.perf_counter()
    WebDriverWait(driver,30).until(lambda d:find_navigation_element(d,label)).click()
    WebDriverWait(driver,30).until(lambda d:markers[label] in d.page_source)
    require(driver.current_package==PACKAGE,'VITALIS left foreground')
    return (time.perf_counter()-start)*1000

def pss(report,index):
    raw=adb('shell','dumpsys','meminfo',PACKAGE)
    (report.out/f'meminfo-{index:03}.txt').write_text(raw,encoding='utf-8')
    match=re.search(r'TOTAL PSS:\s*(\d+)',raw) or re.search(r'^\s*TOTAL\s+(\d+)',raw,re.M)
    require(match is not None,'Total PSS unavailable in meminfo')
    value=int(match.group(1));require(value>0,'Invalid PSS')
    return value

def sample(report,name,action):
    unavailable=[];values={}
    def execute():
        try: values.update(action())
        except EvidenceUnavailable as error: unavailable.append(str(error))
    report.case(name,execute,'Profile Android '+report.suite)
    case=report.cases[-1]
    if unavailable: case.update(status='BLOCKED',detail=unavailable[0])
    elif case['status']=='PASS': case['detail']=json.dumps(values)
    report.metrics.setdefault('samples',[]).append({'name':name,'status':case['status'],'measurements':values})
    (report.out/f'sample-{len(report.cases):03}.json').write_text(json.dumps(values,indent=2),encoding='utf-8')
    if len(report.cases) in [1,report.minimum_cases//2,report.minimum_cases]:
        driver.save_screenshot(str(report.out/f'screen-{len(report.cases):03}.png'))
        (report.out/f'hierarchy-{len(report.cases):03}.xml').write_text(driver.page_source,encoding='utf-8')

def resources(report,index):
    total=pss(report,index)
    cpu=adb('shell','dumpsys','cpuinfo')
    (report.out/f'cpuinfo-{index:03}.txt').write_text(cpu,encoding='utf-8')
    match=re.search(r'([\d.]+)%\s+\d+/'+re.escape(PACKAGE),cpu)
    return dict(total_pss_kb=total,cpu_percent=float(match.group(1)) if match else None,
                cpu_state='measured' if match else 'unavailable',battery_thermal='not physical sensors in this container')

def capture(report,log_offset):
    text=log_file.read_text(errors='replace')[log_offset:]
    (report.out/'driver-request-log.txt').write_text(text,encoding='utf-8')
    report.metrics.update(appium_http_metrics(text))
    raw=adb('logcat','-d');(report.out/'android.log').write_text(raw,encoding='utf-8')
    crash=adb('logcat','-d','-b','crash');(report.out/'crash.log').write_text(crash,encoding='utf-8')
    if PACKAGE in crash and report.cases:
        report.cases[-1].update(status='FAIL',detail='Attributable crash in retained crash.log')

try:
    # Recheck ownership before any fixture write or install; no personal handset is permitted.
    container=os.environ['QA_ANDROID_CONTAINER']
    label=subprocess.run(['docker','inspect','--format','{{index .Config.Labels "com.vitalis.ci"}}',container],
                         check=True,capture_output=True,text=True,timeout=10).stdout.strip()
    validate_environment(os.environ['ANDROID_SERIAL'],os.environ.get('GITHUB_ACTIONS',''),
                         adb('shell','getprop','ro.kernel.qemu'),adb('shell','getprop','ro.hardware').strip(),label,os.environ.get('GITHUB_RUN_ID',''))
    setup=Report(suites[0],minimum_cases=case_count(suites[0]))
    driver=connect()
    WebDriverWait(driver,90).until(lambda d:'Open Model Library' in d.page_source)
    seed(setup,chat_count=100)
    driver.quit();driver=None
    profile=ROOT/'.qa-apk/app-profile.apk'
    expected=(ROOT/'.qa-apk/profile.sha256').read_text().strip()
    with profile.open('rb') as stream: actual=hashlib.file_digest(stream,'sha256').hexdigest()
    require(actual==expected,'Profile APK identity mismatch')
    adb('install','-r',str(profile))
    driver=connect();ready()
    for label in ['Models','Saved','Settings','Chats']: tab(label)
    environment=dict(policy_version=POLICY['policy_version'],android_api=adb('shell','getprop','ro.build.version.sdk').strip(),
        abi=adb('shell','getprop','ro.product.cpu.abi').strip(),mode='profile',
        android_image='redroid-arm64-dc2024a9',screen='720x1280',cpus=3,memory_gib=6,
        host_cpu=host_cpu_identity())
    for suite in suites:
        report=Report(suite,minimum_cases=case_count(suite))
        report.metrics.update(environment=environment,scope='Native ARM Android CI profile APK; not physical-phone performance',
                              apk_source=(ROOT/'.qa-apk/source.txt').read_text().strip())
        offset=len(log_file.read_text(errors='replace'))
        tab('Chats')
        if suite=='endurance':
            report.metrics['warm_baseline_pss_kb']=pss(report,0)
            report.metrics['minimum_soak_seconds']=case_count(suite)*POLICY['soak_interval_seconds']
        for index in range(case_count(suite)):
            target=['Models','Saved','Settings','Chats'][index%4]
            if suite=='latency':
                source=['Chats','Models','Saved','Settings'][index%4]
                target=['Models','Saved','Settings','Chats'][index%4]
                def action(source=source,target=target):
                    tab(source);duration=tab(target)
                    require(duration<=POLICY['ui_action_budget_ms'],'CI UI readiness budget exceeded')
                    return dict(ui_ready_ms=duration,source=source,target=target)
                sample(report,f'Latency {index+1:02}: {source} to {target}',action)
            elif suite=='endurance':
                def action(target=target,index=index):
                    start=time.perf_counter();duration=tab(target)
                    time.sleep(max(0,POLICY['soak_interval_seconds']-(time.perf_counter()-start)))
                    ready();return dict(ui_ready_ms=duration,total_pss_kb=pss(report,index+1),cycle_seconds=time.perf_counter()-start)
                sample(report,f'Soak cycle {index+1:02}',action)
            elif suite=='startup':
                cold=index%2==0
                def action(cold=cold):
                    if cold: adb('shell','am','force-stop',PACKAGE)
                    else: adb('shell','input','keyevent','KEYCODE_HOME')
                    start=time.perf_counter();raw=adb('shell','am','start','-W','-n',PACKAGE+'/.MainActivity');ready()
                    elapsed=(time.perf_counter()-start)*1000
                    require(elapsed<=POLICY['startup_budget_ms'],'CI launch readiness budget exceeded')
                    native=re.search(r'TotalTime:\s*(\d+)',raw)
                    return dict(launch_type='stopped-process' if cold else 'background-resume',flutter_controls_ready_ms=elapsed,
                                android_total_time_ms=int(native.group(1)) if native else None,android_launch_output=raw)
                sample(report,f'Startup {index+1:02}: '+('cold' if cold else 'resume'),action)
            elif suite=='smoothness':
                def action(index=index):
                    tab('Chats');adb('shell','dumpsys','gfxinfo',PACKAGE,'reset')
                    driver.execute_script('mobile: scrollGesture',{'left':20,'top':250,'width':650,'height':600,
                        'direction':'down' if index%2==0 else 'up','percent':0.9})
                    raw=adb('shell','dumpsys','gfxinfo',PACKAGE,'framestats')
                    (report.out/f'framestats-{index+1:03}.txt').write_text(raw,encoding='utf-8')
                    durations=frame_durations(raw);ready()
                    if not durations: raise EvidenceUnavailable('Android window frame samples unavailable; Flutter raster timing is not instrumented by this APK')
                    return dict(window_frames=len(durations),window_frame_median_ms=percentile(durations,.5),
                                window_frame_p95_ms=percentile(durations,.95),scope='Android window timings; not Flutter engine build/raster measurements')
                sample(report,f'Scroll frame sample {index+1:02}',action)
            elif suite=='resources':
                def action(target=target,index=index):
                    tab(target);return resources(report,index+1)
                sample(report,f'Resource snapshot {index+1:02}: {target}',action)
            elif suite=='recovery':
                mode=index%5
                def action(mode=mode,target=target):
                    tab(target)
                    if mode in [0,1]: driver.background_app(1 if mode==0 else 3)
                    elif mode==2:
                        adb('shell','am','force-stop',PACKAGE);driver.activate_app(PACKAGE)
                    else:
                        adb('shell','settings','put','system','accelerometer_rotation','0')
                        adb('shell','settings','put','system','user_rotation','1' if mode==3 else '0')
                    ready();tab('Chats')
                    require('CI fixture' in driver.page_source,'Saved fixture not visible after lifecycle recovery')
                    return dict(event=['short background','long background','explicit force-stop/relaunch','landscape','portrait'][mode],
                                saved_chat_visible=True,scope='UI lifecycle and retained saved-history recovery; force-stop is not ordinary process death')
                sample(report,f'Recovery {index+1:02}: condition {mode}',action)
            if sum(c['status']=='FAIL' for c in report.cases)>=POLICY['max_failures']:
                for remaining in range(index+1,case_count(suite)): report.blocked(f'{suite} case {remaining+1}','Stopped after repeated failures; see preceding evidence')
                break
        if suite=='endurance':
            time.sleep(POLICY['cooldown_seconds']);report.metrics['cooldown_pss_kb']=pss(report,case_count(suite)+1)
            report.metrics['cooldown_pss_growth_percent']=(report.metrics['cooldown_pss_kb']/report.metrics['warm_baseline_pss_kb']-1)*100
            report.metrics['scope']='20 paced cycles, minimum four-minute bounded soak; not multi-hour endurance or a physical memory-leak verdict'
        if suite=='resources':
            (report.out/'battery.txt').write_text(adb('shell','dumpsys','battery'),encoding='utf-8')
            (report.out/'thermal.txt').write_text(adb('shell','dumpsys','thermalservice',check=False),encoding='utf-8')
            report.metrics['physical_battery_thermal']='UNSUPPORTED in Android container; no physical energy or temperature verdict'
        capture(report,offset)
        failed=bool(report.write()) or failed
except Exception:
    failure=traceback.format_exc()
    for suite in suites:
        report=Report(suite,minimum_cases=case_count(suite))
        if (report.out/'results.json').exists(): continue
        (report.out/'setup-failure.txt').write_text(failure,encoding='utf-8')
        for index in range(case_count(suite)): report.blocked(f'{suite} case {index+1}','Environment/prerequisite failure; see setup-failure.txt')
        report.write()
    failed=True
finally:
    if driver is not None: driver.quit()
raise SystemExit(1 if failed else 0)
