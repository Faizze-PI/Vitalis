param(
    [Parameter(Mandatory=$true)][string]$Bundle,
    [Parameter(Mandatory=$true)][string]$Dumpbin,
    [Parameter(Mandatory=$true)][string]$Report
)
$ErrorActionPreference = 'Stop'
$Bundle = (Resolve-Path -LiteralPath $Bundle).Path
$Files = @(Get-ChildItem -LiteralPath $Bundle -File | Where-Object Extension -in @('.dll','.exe'))
$Names = @($Files.Name | ForEach-Object { $_.ToLowerInvariant() })
$SystemLibraries = @(
    'advapi32.dll','bcrypt.dll','crypt32.dll','d3d9.dll','d3d11.dll','d3dcompiler_47.dll',
    'dbghelp.dll','dwmapi.dll','dxgi.dll','gdi32.dll','imm32.dll','iphlpapi.dll',
    'kernel32.dll','ntdll.dll','ole32.dll','oleacc.dll','oleaut32.dll','opengl32.dll',
    'propsys.dll','psapi.dll','rpcrt4.dll','shell32.dll','shlwapi.dll','uiautomationcore.dll',
    'user32.dll','userenv.dll','version.dll','winhttp.dll','winmm.dll','ws2_32.dll'
)
foreach ($Name in @('VITALIS.exe','flutter_windows.dll','llama.dll','ggml.dll','ggml-base.dll','ggml-cpu.dll','sqlite3.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    if ($Name.ToLowerInvariant() -notin $Names) { throw "Required bundled runtime is missing: $Name" }
}
$Results = @()
$Failures = @()
foreach ($File in $Files) {
    $Headers = & $Dumpbin /headers $File.FullName
    if ($LASTEXITCODE -or -not ($Headers -match '8664 machine \(x64\)')) { $Failures += "Not a valid x64 runtime: $($File.Name)" }
    $Output = & $Dumpbin /dependents $File.FullName
    if ($LASTEXITCODE) { throw "Could not inspect dependencies: $($File.Name)" }
    $Dependencies = @($Output | Where-Object { $_ -match '^\s+[A-Za-z0-9_.-]+\.dll\s*$' } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    foreach ($Dependency in $Dependencies) {
        if ($Dependency -notin $Names -and $Dependency -notin $SystemLibraries -and $Dependency -notmatch '^(api-ms-|ext-ms-)') {
            $Failures += "$($File.Name) has an unbundled non-system dependency: $Dependency"
        }
    }
    $Results += @{file=$File.Name; sha256=(Get-FileHash $File.FullName -Algorithm SHA256).Hash.ToLowerInvariant(); dependencies=$Dependencies}
}
if ('dartjni.dll' -in $Names -or 'jvm.dll' -in $Names) { $Failures += 'The Android-only JNI bridge must not enter the Windows preview.' }
$Exports = & $Dumpbin /exports (Join-Path $Bundle 'llama.dll')
foreach ($Symbol in @('llama_model_load_from_file','llama_decode','vitalis_cancel_token_request','vitalis_cancel_token_is_acknowledged')) {
    if (-not ($Exports -match "\s$Symbol\s*$")) { $Failures += "Missing native symbol: $Symbol" }
}
$Signing = (Get-AuthenticodeSignature (Join-Path $Bundle 'VITALIS.exe')).Status.ToString()
if ($Signing -ne 'NotSigned') { $Failures += "Preview signing status is not positively unsigned: $Signing" }
$Forbidden = @(Get-ChildItem -LiteralPath $Bundle -Recurse -File | Where-Object { $_.Extension -in @('.gguf','.jks','.keystore','.pdb','.db','.sqlite') })
if ($Forbidden.Count) { $Failures += 'Unexpected model, signing material, debug symbols or user database in package.' }
@{files=$Results; signing=$Signing; failures=$Failures} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Report
if ($Failures.Count) { throw ($Failures -join [Environment]::NewLine) }
Write-Output "Windows bundle passed x64, dependency, symbol, payload and unsigned-preview checks ($($Files.Count) PE files)."
