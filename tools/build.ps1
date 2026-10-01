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
# KI-Modelltexturen sind JPGs: verlustfrei importiert blähen sie die APK nur auf. Neue Importe auf WebP (verlustbehaftet)
# umstellen und dann neu importieren.
$lossless = Get-ChildItem (Join-Path $gamePath 'assets/props'), (Join-Path $gamePath 'assets/cars'), (Join-Path $gamePath 'dioramas') -Filter '*.jpg.import' |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^compress/mode=0\r?$' }
if ($lossless) {
    foreach ($file in $lossless) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^compress/mode=0(\r?)$', 'compress/mode=1$1' -replace '(?m)^compress/lossy_quality=0\.7(\r?)$', 'compress/lossy_quality=0.8$1'
        [IO.File]::WriteAllText($file.FullName, $text)
    }
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--editor','--import','--quit')
}
# Bausatz-Texturen der Diorama-Häuser (tools/make_kit_textures.py): in 3D brauchen sie Mipmaps; Grafikkartenkompression spart Speicher.
$kit = Get-ChildItem (Join-Path $gamePath 'assets/kit'), (Join-Path $gamePath 'assets/event') -Filter '*.png.import' -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^mipmaps/generate=false\r?$' }
if ($kit) {
    foreach ($file in $kit) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^mipmaps/generate=false(\r?)$', 'mipmaps/generate=true$1' -replace '(?m)^compress/mode=0(\r?)$', 'compress/mode=2$1' -replace '(?m)^compress/high_quality=false(\r?)$', 'compress/high_quality=true$1'
        if ($file.Name -like '*_n.png.import') { $text = $text -replace '(?m)^compress/normal_map=0(\r?)$', 'compress/normal_map=1$1' }
        [IO.File]::WriteAllText($file.FullName, $text)
    }
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--editor','--import','--quit')
}
# Motorschichten (tools/make_engine_sounds.py): Godot importiert WAV standardmäßig als QOA (verlustbehaftet); Motoren bleiben verlustfrei.
$engines = Get-ChildItem (Join-Path $gamePath 'assets/sfx') -Recurse -Filter '*.wav.import' -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^compress/mode=2\r?$' }
if ($engines) {
    foreach ($file in $engines) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^compress/mode=2(\r?)$', 'compress/mode=0$1'
        [IO.File]::WriteAllText($file.FullName, $text)
    }
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--editor','--import','--quit')
}
foreach ($test in @('test_core','test_flow','test_tracks','test_air','test_diorama','test_collision')) {
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--quit-after','180','--script',"res://tests/$test.gd")
}
if ($Target -eq 'Test') { exit 0 }
New-Item -ItemType Directory -Force (Join-Path $projectRoot 'builds') | Out-Null
if ($Target -in @('All','Windows')) {
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--export-release','Windows',(Join-Path $projectRoot 'builds/Draw2Race.exe'))
}
if ($Target -in @('All','Android')) {
    # Godot-Bibliotheken (je ~100 MB) nicht im Repo: bei Bedarf aus der Exportvorlage nachziehen.
    $libs = Join-Path $gamePath 'android/build/libs'
    if (-not (Test-Path (Join-Path $libs 'debug/godot-lib.template_debug.aar'))) {
        $tmp = Join-Path $env:TEMP 'draw2race-android-template'
        Expand-Archive -LiteralPath (Join-Path $projectRoot '.tools/export/templates/android_source.zip') -DestinationPath $tmp -Force
        Copy-Item -Recurse -Force (Join-Path $tmp 'libs') (Join-Path $gamePath 'android/build/')
        Remove-Item -Recurse -Force $tmp
    }
    # Fester Projekt-Debugschlüssel: Updates auf dem Gerät bleiben möglich, auch wenn %APPDATA%\Godot neu entsteht.
    $keystore = Join-Path $projectRoot '.tools/draw2race-debug.keystore'
    if (Test-Path -LiteralPath $keystore) {
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $keystore
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
        $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
    }
    Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--export-debug','Android',(Join-Path $projectRoot 'builds/Draw2Race.apk'))
    # Release-Datei für GitHub: Die Update-Funktion erwartet genau "Draw2Race-<version>.apk" (version = config/version).
    $version = (Select-String -LiteralPath (Join-Path $gamePath 'project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
    $preset = Select-String -LiteralPath (Join-Path $gamePath 'export_presets.cfg') -Pattern '^version/name="(.+)"'
    if ($preset.Matches[0].Groups[1].Value -ne $version) { throw "Version in project.godot ($version) und Exportprofil unterscheiden sich." }
    Copy-Item -LiteralPath (Join-Path $projectRoot 'builds/Draw2Race.apk') -Destination (Join-Path $projectRoot "builds/Draw2Race-$version.apk") -Force
}
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/OFL.txt') -Destination (Join-Path $projectRoot 'builds/Outfit-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-LICENSE.txt') -Destination (Join-Path $projectRoot 'builds/Godot-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-COPYRIGHT.txt') -Destination (Join-Path $projectRoot 'builds/Godot-COPYRIGHT.txt') -Force
