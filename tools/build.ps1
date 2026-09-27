param([ValidateSet('All','Windows','Android','Test')][string]$Target='All')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/Godot_v4.6.1-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Godot 4.6.1 fehlt. Zuerst tools/setup.ps1 ausführen.' }
$gamePath = Join-Path $projectRoot 'game'
function Invoke-Godot([string[]]$Arguments) {
    $output = & $engine @Arguments 2>&1
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -match 'SCRIPT ERROR|^ERROR:|FAIL:')) { throw "Godot fehlgeschlagen: $Arguments" }
}
Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--editor','--import','--quit')
foreach ($test in @('test_core','test_flow','test_tracks')) {
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--quit-after','180','--script',"res://tests/$test.gd")
}
if ($Target -eq 'Test') { exit 0 }
New-Item -ItemType Directory -Force (Join-Path $projectRoot 'builds') | Out-Null
if ($Target -in @('All','Windows')) {
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--export-release','Windows',(Join-Path $projectRoot 'builds/Draw2Race.exe'))
}
if ($Target -in @('All','Android')) {
    # Fester Projekt-Debugschlüssel: Updates auf dem Gerät bleiben möglich, auch wenn %APPDATA%\Godot neu entsteht.
    $keystore = Join-Path $projectRoot '.tools/draw2race-debug.keystore'
    if (Test-Path -LiteralPath $keystore) {
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $keystore
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
    }
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--export-debug','Android',(Join-Path $projectRoot 'builds/Draw2Race.apk'))
}
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/OFL.txt') -Destination (Join-Path $projectRoot 'builds/Outfit-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-LICENSE.txt') -Destination (Join-Path $projectRoot 'builds/Godot-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-COPYRIGHT.txt') -Destination (Join-Path $projectRoot 'builds/Godot-COPYRIGHT.txt') -Force
