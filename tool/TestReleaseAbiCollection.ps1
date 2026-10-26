$ErrorActionPreference = 'Stop'
$parseErrors = $null
$tokens = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'run_android_release_gate.ps1'), [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Release launcher has syntax errors.' }
$assignment = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$NativeAbis'
}, $true))
if ($assignment.Count -ne 1) { throw 'Expected one native ABI collection assignment.' }
$collect = [scriptblock]::Create($assignment[0].Extent.Text)
foreach ($case in @(
    @{ Names = @('lib/arm64-v8a/libapp.so', 'lib/arm64-v8a/libflutter.so'); Expected = @('arm64-v8a') },
    @{ Names = @('assets/model.txt'); Expected = @() },
    @{ Names = @('lib/x86_64/libapp.so'); Expected = @('x86_64') },
    @{ Names = @('lib/x86_64/libapp.so', 'lib/arm64-v8a/libflutter.so'); Expected = @('arm64-v8a', 'x86_64') }
)) {
    $Names = $case.Names
    . $collect
    if (@($NativeAbis).Count -ne $case.Expected.Count) { throw 'Incorrect ABI collection count.' }
    for ($index = 0; $index -lt $case.Expected.Count; $index++) {
        if ($NativeAbis[$index] -ne $case.Expected[$index]) {
            throw 'ABI collection indexed a scalar string instead of an ABI entry.'
        }
    }
}
'Release ABI collection regression passed: single, absent, foreign and mixed ABIs.'
