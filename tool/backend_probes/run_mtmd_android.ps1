param(
    [Parameter(Mandatory)][string] $AndroidSdk,
    [Parameter(Mandatory)][string] $OutputDirectory,
    [Parameter(Mandatory)][int] $Parallelism
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$policy = Get-Content (Join-Path $repo 'tool/toolchain_policy.json') -Raw | ConvertFrom-Json
$lock = Get-Content (Join-Path $repo 'third_party/llm_llamacpp/native/llama_cpp.lock.json') -Raw | ConvertFrom-Json
if ($Parallelism -lt 1 -or $Parallelism -gt [Environment]::ProcessorCount) {
    throw 'Parallelism must be positive and no greater than the available logical processors.'
}
if ($policy.ndk -ne $lock.androidNdk -or $policy.minSdk -ne $lock.androidApi) {
    throw 'The native lock and Android toolchain policy disagree.'
}
$ndk = Join-Path $AndroidSdk "ndk/$($policy.ndk)"
if (!(Test-Path (Join-Path $ndk 'build/cmake/android.toolchain.cmake'))) {
    throw 'Install the pinned NDK before running this probe.'
}
$archive = Join-Path $repo ".native-build/llama-$($lock.commit)/source.tar.gz"
if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant() -ne $lock.archiveSha256) {
    throw 'The cached source archive does not match the immutable native lock.'
}
if (Test-Path -LiteralPath $OutputDirectory) {
    throw 'Use a new output directory; previous probe evidence is never overwritten.'
}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$sourceRoot = Join-Path $output 'source'
New-Item -ItemType Directory -Path $sourceRoot | Out-Null
& tar -xzf $archive -C $sourceRoot
if ($LASTEXITCODE -ne 0) { throw 'Locked-source extraction failed.' }
$source = Join-Path $sourceRoot "llama.cpp-$($lock.commit)"
$build = Join-Path $output 'android-arm64'
$cmake = (Get-Command cmake -ErrorAction Stop).Source
$ninja = (Get-Command ninja -ErrorAction Stop).Source
$arguments = @(
    '-S', $source, '-B', $build, '-G', 'Ninja',
    "-DCMAKE_MAKE_PROGRAM=$ninja",
    "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake",
    "-DANDROID_ABI=$($policy.androidAbi)", "-DANDROID_PLATFORM=android-$($policy.minSdk)",
    '-DANDROID_STL=c++_static', '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_SHARED_LIBS=ON',
    '-DGGML_NATIVE=OFF', '-DGGML_OPENMP=OFF', '-DGGML_BACKEND_DL=ON', '-DGGML_VULKAN=OFF',
    '-DLLAMA_STANDALONE=OFF', '-DLLAMA_BUILD_COMMON=OFF', '-DLLAMA_BUILD_APP=OFF',
    '-DLLAMA_BUILD_MTMD=ON', '-DLLAMA_BUILD_TESTS=OFF', '-DLLAMA_BUILD_EXAMPLES=OFF',
    '-DLLAMA_BUILD_SERVER=OFF', '-DLLAMA_BUILD_TOOLS=OFF', '-DLLAMA_CURL=OFF',
    '-DMTMD_VIDEO=OFF', '-DLLAMA_SUBPROCESS=OFF'
)
& $cmake @arguments *> (Join-Path $output 'configure.txt')
if ($LASTEXITCODE -ne 0) { throw "Configure failed; inspect $output/configure.txt" }
& $cmake --build $build --target mtmd --parallel $Parallelism *> (Join-Path $output 'build.txt')
if ($LASTEXITCODE -ne 0) { throw "Build failed; inspect $output/build.txt" }
$libraries = @(Get-ChildItem $build -Recurse -Filter '*.so' | ForEach-Object {
    @{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
})
if (!($libraries | Where-Object name -eq 'libmtmd.so')) { throw 'The vision library was not produced.' }
@{
    status = 'ANDROID_COMPILE_ONLY'; commit = $lock.commit; sourceSha256 = $lock.archiveSha256
    minSdk = $policy.minSdk; abi = $policy.androidAbi; ndk = $policy.ndk
    libraries = $libraries; imageInference = 'NOT_TESTED'; encoderCancellation = 'NOT_TESTED'
    productionPackaging = 'NOT_ENABLED'; toolsAndSubprocess = 'DISABLED'
} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $output 'result.json')
Write-Output "Android vision compile probe completed: $output/result.json"
