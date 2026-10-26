param()
$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path $PSScriptRoot -Parent
$Master = Join-Path $ProjectRoot 'assets/brand/vitalis-symbol.png'
if (-not (Test-Path -LiteralPath $Master)) { throw 'VITALIS logo master is missing.' }
$Magick = (Get-Command magick -ErrorAction Stop).Source
# Android's documented adaptive-icon canvas and unclipped logo region, in dp.
$CanvasDp = 108
$MarkDp = 66
$Densities = @{mdpi=1;hdpi=1.5;xhdpi=2;xxhdpi=3;xxxhdpi=4}
foreach ($Entry in $Densities.GetEnumerator()) {
    $Destination = Join-Path $ProjectRoot "android/app/src/main/res/mipmap-$($Entry.Key)"
    if (-not (Test-Path -LiteralPath $Destination)) { throw "Missing Android resource directory: $Destination" }
    $Canvas = [int]($CanvasDp * $Entry.Value)
    $Mark = [int]($MarkDp * $Entry.Value)
    & $Magick $Master -trim +repage -resize "${Mark}x${Mark}" -background none -gravity center -extent "${Canvas}x${Canvas}" (Join-Path $Destination 'ic_launcher_foreground.png')
    if ($LASTEXITCODE) { throw 'Foreground export failed.' }
    & $Magick -size "${Canvas}x${Canvas}" 'xc:#FAFAF8' (Join-Path $Destination 'ic_launcher_background.png')
    if ($LASTEXITCODE) { throw 'Background export failed.' }
}
$WindowsResources = Join-Path $ProjectRoot 'windows/runner/resources'
if (Test-Path -LiteralPath $WindowsResources) {
    & $Magick -size 256x256 xc:none -fill '#FAFAF8' -draw 'roundrectangle 0,0 255,255 52,52' '(' $Master -trim +repage -resize 192x192 ')' -gravity center -compose over -composite -define icon:auto-resize=256,128,64,48,32,24,16 (Join-Path $WindowsResources 'app_icon.ico')
    if ($LASTEXITCODE) { throw 'Windows icon export failed.' }
}
Write-Output 'VITALIS icon exports refreshed from the checked-in master.'
