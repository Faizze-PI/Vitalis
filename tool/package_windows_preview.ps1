param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$Project = Split-Path $PSScriptRoot -Parent
$Build = Join-Path $Project 'build/windows/x64/runner/Release'
if (-not (Test-Path (Join-Path $Build 'VITALIS.exe'))) { throw 'Build the Windows release first.' }
if (git -C $Project status --porcelain) { throw 'Checkpoint the intended source before packaging.' }
$VersionLine = Get-Content (Join-Path $Project 'pubspec.yaml') | Where-Object { $_ -match '^version:' }
$Version = ($VersionLine -replace '^version:\s*','').Split('+')[0]
$Source = (git -C $Project rev-parse HEAD).Trim()
$PackageName = "VITALIS-$Version-windows-x64"
$Destination = Join-Path $OutputDirectory $PackageName
if (Test-Path -LiteralPath $Destination) { throw 'Choose a fresh output directory; existing packages are preserved.' }
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
# An incremental output folder can retain old plugin DLLs. CMake's completed
# install manifest is the authority for this build; preserve, but never ship,
# unrelated/stale files from previous builds.
$InstallManifest = Join-Path $Project 'build/windows/x64/install_manifest.txt'
if (-not (Test-Path -LiteralPath $InstallManifest)) { throw 'The completed build install manifest is missing.' }
$BuildRoot = (Resolve-Path -LiteralPath $Build).Path
foreach ($InstalledFile in (Get-Content -LiteralPath $InstallManifest)) {
    $InstalledFile = $InstalledFile.Trim()
    if (-not $InstalledFile) { continue }
    $InstalledPath = (Resolve-Path -LiteralPath $InstalledFile).Path
    if (-not $InstalledPath.StartsWith($BuildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'An installation manifest entry escapes the application output folder.'
    }
    $Relative = [IO.Path]::GetRelativePath($BuildRoot, $InstalledPath)
    $Target = Join-Path $Destination $Relative
    New-Item -ItemType Directory -Path (Split-Path $Target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $InstalledPath -Destination $Target
}
# CMake omits the no-op install when the runner is already in its destination.
# Add this one known build target explicitly, never the rest of the output glob.
Copy-Item -LiteralPath (Join-Path $Build 'VITALIS.exe') -Destination $Destination

# The locked sqflite_common_ffi v2 package supplies this SQLite runtime.
# Resolve its exact package, never download a DLL or search arbitrary directories.
$ConfigFile = Join-Path $Project '.dart_tool/package_config.json'
$Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
$Package = @($Config.packages | Where-Object name -eq 'sqflite_common_ffi')
if ($Package.Count -ne 1) { throw 'Cannot resolve the locked SQLite package.' }
$PackageUri = [Uri]::new([Uri]::new($ConfigFile), $Package[0].rootUri)
$Sqlite = Join-Path $PackageUri.LocalPath 'lib/src/windows/sqlite3.dll'
if (-not (Test-Path -LiteralPath $Sqlite)) { throw 'Locked package SQLite runtime is missing.' }
Copy-Item -LiteralPath $Sqlite -Destination $Destination
$Licences = Join-Path $Destination 'licences'
New-Item -ItemType Directory -Path $Licences | Out-Null
Copy-Item -LiteralPath (Join-Path $PackageUri.LocalPath 'LICENSE') -Destination (Join-Path $Licences 'sqflite_common_ffi-LICENSE')
Copy-Item -LiteralPath (Join-Path $Project 'third_party/llm_llamacpp/LICENSE') -Destination (Join-Path $Licences 'llm_llamacpp-LICENSE')
$NativeLock = Get-Content (Join-Path $Project 'third_party/llm_llamacpp/native/llama_cpp.lock.json') -Raw | ConvertFrom-Json
$NativeCommit = $NativeLock.commit
if (-not $NativeCommit) { throw 'The native source lock has no commit.' }
$NativeSource = Join-Path $Project ".native-build/llama-$NativeCommit/llama.cpp-$NativeCommit"
Copy-Item -LiteralPath (Join-Path $NativeSource 'LICENSE') -Destination (Join-Path $Licences 'llama.cpp-LICENSE')
Copy-Item -LiteralPath (Join-Path $NativeSource 'licenses/LICENSE-jsonhpp') -Destination (Join-Path $Licences 'jsonhpp-LICENSE')

# Only use the redistributable directory of the installed C++ build tools.
$VsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$VisualStudio = (& $VsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath).Trim()
if (-not $VisualStudio) { throw 'C++ build tools were not found.' }
$Redist = Join-Path $VisualStudio 'VC/Redist/MSVC'
$Crt = @(Get-ChildItem -LiteralPath $Redist -Directory | Where-Object Name -match '^\d+\.' | Sort-Object Name -Descending | ForEach-Object {
    Get-ChildItem -Path (Join-Path $_.FullName 'x64/Microsoft.VC*.CRT') -Directory
} | Select-Object -First 1)
if ($Crt.Count -ne 1) { throw 'The build-tool C++ redistributable is missing.' }
foreach ($Name in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    Copy-Item -LiteralPath (Join-Path $Crt[0].FullName $Name) -Destination $Destination
}
foreach ($Name in @('LICENSE','NOTICE','THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $Project $Name) -Destination $Destination
}
foreach ($Name in @('llama.dll','ggml.dll','ggml-base.dll','ggml-cpu.dll','flutter_windows.dll','sqlite3.dll')) {
    if (-not (Test-Path (Join-Path $Destination $Name))) { throw "Required runtime missing: $Name" }
}
if (Get-ChildItem -LiteralPath $Destination -Recurse -File | Where-Object Extension -in @('.gguf','.jks','.keystore','.pdb')) {
    throw 'Unexpected model, signing material or debug symbols in preview.'
}
$Tools = Get-ChildItem -LiteralPath (Join-Path $VisualStudio 'VC/Tools/MSVC') -Directory |
    Where-Object Name -match '^\d+\.' | Sort-Object Name -Descending | Select-Object -First 1
if (-not $Tools) { throw 'Cannot locate the build-tool dependency inspector.' }
$Dumpbin = Join-Path $Tools.FullName 'bin/Hostx64/x64/dumpbin.exe'
& (Join-Path $PSScriptRoot 'verify_windows_bundle.ps1') -Bundle $Destination -Dumpbin $Dumpbin -Report (Join-Path $OutputDirectory 'bundle-inspection.json')
@{ source=$Source; version=$Version; platform='windows-x64'; backend='cpu'; signing='unsigned-testing-preview'; sqlite_sha256=(Get-FileHash $Sqlite -Algorithm SHA256).Hash } |
    ConvertTo-Json | Set-Content (Join-Path $Destination 'BUILD_PROVENANCE.json')
@'
VITALIS Windows testing preview

Extract the complete ZIP to a writable folder, then open VITALIS.exe.
Keep all DLLs and the data folder together. Model weights download separately.
Conversations and models use application-controlled user storage, not this folder.
This preview is unsigned and is not production-ratified.
'@ | Set-Content (Join-Path $Destination 'START_HERE.txt')
$Archive = Join-Path $OutputDirectory "$PackageName.zip"
if (Test-Path -LiteralPath $Archive) { throw 'An archive already exists at this destination.' }
Compress-Archive -LiteralPath $Destination -DestinationPath $Archive
"$((Get-FileHash $Archive -Algorithm SHA256).Hash.ToLowerInvariant())  $PackageName.zip" |
    Set-Content (Join-Path $OutputDirectory 'SHA256SUMS-windows.txt')
Write-Output $Archive
