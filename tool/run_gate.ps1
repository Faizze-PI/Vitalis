param(
    [string[]] $FlutterArguments
)

# Keep Flutter flags out of PowerShell's advanced-script common parameters.
$ErrorActionPreference = 'Stop'
$ArgumentPrefix = 'VITALIS_ARGS64_' # hardcode: HC-073
if ($FlutterArguments.Count -eq 1 -and $FlutterArguments[0].StartsWith($ArgumentPrefix)) {
    if ($args.Count -gt 0) {
        throw 'Use either encoded or ordinary Flutter arguments, not both.'
    }
    try {
        $DecodedArguments = ConvertFrom-Json -NoEnumerate -InputObject (
            [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String(
                $FlutterArguments[0].Substring($ArgumentPrefix.Length)
            ))
        )
    } catch {
        throw 'Encoded Flutter arguments must contain a JSON string array.'
    }
    if ($DecodedArguments -isnot [Array]) {
        throw 'Encoded Flutter arguments must contain a JSON string array.'
    }
    foreach ($ArgumentValue in $DecodedArguments) {
        if ($ArgumentValue -isnot [string]) {
            throw 'Encoded Flutter arguments must contain a JSON string array.'
        }
    }
    $FlutterArguments = @($DecodedArguments)
} else {
    $FlutterArguments = @($FlutterArguments) + @($args)
}
$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$PolicyPath = Join-Path $PSScriptRoot 'toolchain_policy.json'
$Policy = Get-Content -LiteralPath $PolicyPath -Raw | ConvertFrom-Json
$FlutterRoot = if ($env:VITALIS_FLUTTER_SDK) {
    $env:VITALIS_FLUTTER_SDK
} else {
    Join-Path $RepositoryRoot '.fvm\flutter_sdk'
}
$Flutter = Join-Path $FlutterRoot 'bin\flutter.bat'
$Dart = Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe'
if ($env:FLUTTER_TOOL_ARGS) {
    throw 'FLUTTER_TOOL_ARGS is unsupported by managed gates; pass explicit Flutter arguments.'
}
if (-not $env:VITALIS_GENERATION_TOKEN) {
    # Native pwsh -File splits colon-bearing unbound options. Transport data,
    # rather than rebuilding a command string or guessing how to join tokens.
    $ArgumentTransport = $ArgumentPrefix + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $FlutterArguments -Compress)
    ))
    & $Dart (Join-Path $PSScriptRoot 'generation_lock.dart') -- `
        (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $PSCommandPath `
        -FlutterArguments $ArgumentTransport
    exit $LASTEXITCODE
}
& $Dart (Join-Path $PSScriptRoot 'generation_lock.dart') --verify
if ($LASTEXITCODE -ne 0) { throw 'Checkout ownership verification failed.' }

if (-not (Test-Path -LiteralPath $Flutter)) {
    throw 'Flutter is missing. Set VITALIS_FLUTTER_SDK or create .fvm/flutter_sdk.'
}
if (-not $env:JAVA_HOME) {
    throw "JAVA_HOME must explicitly select JDK $($Policy.jdk)."
}

& (Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe') `
    (Join-Path $PSScriptRoot 'verify_toolchain_policy.dart')
if ($LASTEXITCODE -ne 0) { throw 'Android declarations differ from toolchain policy.' }
$FlutterVersionJson = & $Flutter --version --machine
if ($LASTEXITCODE -ne 0) { throw 'Flutter version discovery failed.' }
$FlutterVersionJson | & (Join-Path $FlutterRoot 'bin\cache\dart-sdk\bin\dart.exe') `
    (Join-Path $PSScriptRoot 'validate_flutter_version.dart') $PolicyPath
if ($LASTEXITCODE -ne 0) { throw 'Flutter/Dart version policy failed.' }
$JavaVersion = (& (Join-Path $env:JAVA_HOME 'bin\java.exe') -version 2>&1 | Select-Object -First 1)
if ($JavaVersion -notmatch ('version "' + [regex]::Escape($Policy.jdk) + '"')) {
    throw "VITALIS requires JDK $($Policy.jdk); selected: $JavaVersion"
}

$SelectedPubCache = if ($env:VITALIS_PUB_CACHE) {
    $env:VITALIS_PUB_CACHE
} else {
    Join-Path $RepositoryRoot '.gate-cache\pub'
}
$SelectedGradleCache = if ($env:VITALIS_GRADLE_CACHE) {
    $env:VITALIS_GRADLE_CACHE
} else {
    Join-Path $RepositoryRoot '.gate-cache\gradle'
}
if ($env:PUB_CACHE) {
    & $Dart (Join-Path $PSScriptRoot 'verify_gate_environment.dart') --same-directory $env:PUB_CACHE $SelectedPubCache
    if ($LASTEXITCODE -ne 0) { throw 'PUB_CACHE conflicts with the selected workspace cache.' }
}
if ($env:GRADLE_USER_HOME) {
    & $Dart (Join-Path $PSScriptRoot 'verify_gate_environment.dart') --same-directory $env:GRADLE_USER_HOME $SelectedGradleCache
    if ($LASTEXITCODE -ne 0) { throw 'GRADLE_USER_HOME conflicts with the selected workspace cache.' }
}
$env:PUB_CACHE = $SelectedPubCache
$env:GRADLE_USER_HOME = $SelectedGradleCache
& $Dart (Join-Path $PSScriptRoot 'verify_gate_environment.dart')
if ($LASTEXITCODE -ne 0) { throw 'Installed toolchain/cache preflight failed.' }
$FlutterConfiguration = & $Flutter config --machine
if ($LASTEXITCODE -ne 0) { throw 'Flutter effective toolchain discovery failed.' }
$FlutterConfiguration | & $Dart (Join-Path $PSScriptRoot 'verify_flutter_selection.dart')
if ($LASTEXITCODE -ne 0) { throw 'Flutter effective JDK/SDK differs from the selected toolchain.' }
New-Item -ItemType Directory -Force $env:PUB_CACHE, $env:GRADLE_USER_HOME | Out-Null

if (-not $FlutterArguments -or $FlutterArguments.Count -eq 0) {
    throw 'Pass a Flutter command, for example: tool/run_gate.ps1 analyze --fatal-warnings'
}
# The version/config preflight above bootstraps Flutter's official CLI snapshot.
# Invoke that same entrypoint directly so cmd.exe cannot reinterpret regex pipes.
$FlutterPackages = Join-Path $FlutterRoot 'packages\flutter_tools\.dart_tool\package_config.json'
$FlutterSnapshot = Join-Path $FlutterRoot 'bin\cache\flutter_tools.snapshot'
& $Dart "--packages=$FlutterPackages" $FlutterSnapshot @FlutterArguments
$FlutterExit = $LASTEXITCODE
if ($FlutterExit -eq 0 -and $FlutterArguments[0] -eq 'clean') {
    & $Dart (Join-Path $PSScriptRoot 'verify_clean_outputs.dart') $RepositoryRoot
    exit $LASTEXITCODE
}
exit $FlutterExit
