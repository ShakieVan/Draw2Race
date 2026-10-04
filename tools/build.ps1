param([ValidateSet('All','Windows','Android','Test')][string]$Target='All', [int]$LockWaitMinutes = 120)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/Godot_v4.6.1-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $engine)) { throw 'Godot 4.6.1 fehlt. Zuerst tools/setup.ps1 ausführen.' }
$gamePath = Join-Path $projectRoot 'game'
function Invoke-Godot([string[]]$Arguments) {
    # Godot schreibt auch auf stderr. Unter Windows PowerShell 5.1 macht "2>&1" daraus Fehlerobjekte, die bei 'Stop' sofort abbrechen –
    # Godot liefe dann mitten im Import verwaist weiter (04.10.2026: ein so abgebrochener Bau hinterließ zehn beschädigte .import-Dateien).
    # Darum läuft Godot immer zu Ende, entschieden wird danach.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $engine @Arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $previousPreference }
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -match 'SCRIPT ERROR|^ERROR:|FAIL:')) { throw "Godot fehlgeschlagen: $Arguments" }
}
# Android-Signatur: Alle Draw2Race-APKs tragen den festen Projekt-Debugschlüssel .tools/draw2race-debug.keystore. Nur dann passt ein
# Update zur installierten App; mit jedem anderen Schlüssel lehnen Android und der Updater (Updater.java) es ab. SHA-256 seines
# Zertifikats (öffentlich, steht in jeder APK; so auch in Release 1.0.0):
$projectCertSha256 = 'e1d49a5df1cbbb1ef0611e2c5c971a351a82c65aaf0770496325b486032057b7'
# version/code aus der Version: X.Y.Z → X·1 000 000 + Y·1 000 + Z (1.0.1 → 1000001, 1.1.0 → 1001000). Er steigt mit jeder höheren
# Version, also auch von jeder Beta zum nächsten Release (Nummernschema in docs/IMPLEMENTIERUNG.md). Bis 1.0.0 wurde von Hand
# gezählt (zuletzt 37); das Schema liegt darüber. Android erlaubt höchstens 2 100 000 000.
function Get-VersionCode([string]$Version) {
    if ($Version -notmatch '^(\d{1,4})\.(\d{1,3})\.(\d{1,3})$') { throw "Version '$Version' passt nicht zum Schema X.Y.Z (nur Ziffern, Y und Z höchstens 999)." }
    $code = [long]$Matches[1] * 1000000 + [long]$Matches[2] * 1000 + [long]$Matches[3]
    if ($code -gt 2100000000) { throw "Version '$Version' ergibt version/code $code – mehr als Android erlaubt." }
    return $code
}
function Find-ApkSigner {
    # apksigner aus dem Android-SDK, das auch Godot benutzt (Editor-Einstellung export/android/android_sdk_path), sonst den üblichen Orten.
    $roots = @()
    $settings = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Godot') -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($file in $settings) {
        $line = Select-String -LiteralPath $file.FullName -Pattern '^export/android/android_sdk_path = "(.+)"' | Select-Object -First 1
        if ($line) { $roots += $line.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $roots += @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ }
    foreach ($root in $roots) {
        $tools = Join-Path $root 'build-tools'
        if (-not (Test-Path -LiteralPath $tools)) { continue }
        $found = Get-ChildItem -LiteralPath $tools -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending | Select-Object -First 1
        if ($found) { return Join-Path $found.FullName 'apksigner.bat' }
    }
    return $null
}
# Vorabprüfung für Android, bevor Import und Tests Minuten kosten.
if ($Target -in @('All','Android')) {
    # Ohne den Projektschlüssel würde Godot still mit seinem eigenen Debugschlüssel (%APPDATA%\Godot) signieren, und erst das Handy meldete
    # beim Update „Signatur passt nicht“.
    $keystore = Join-Path $projectRoot '.tools/draw2race-debug.keystore'
    if (-not (Test-Path -LiteralPath $keystore)) {
        throw ("Projekt-Debugschlüssel fehlt: $keystore`n" +
            "Ohne ihn wäre die APK mit einem anderen Schlüssel signiert, und In-App-Updates scheiterten auf jedem Handy mit 'Signatur passt nicht'.`n" +
            "Die Datei aus der Sicherung zurückkopieren. Nicht neu erzeugen: Mit einem neuen Schlüssel müsste Draw2Race auf jedem Handy " +
            "deinstalliert und neu installiert werden, der Spielstand ginge dabei verloren.")
    }
    if (-not (Find-ApkSigner)) { throw 'apksigner (Android-SDK, build-tools) nicht gefunden – ohne ihn lässt sich die Signatur der APK nicht prüfen.' }
    # Versionen: project.godot und Exportprofil müssen übereinstimmen; version/code wird aus der Version berechnet und eingetragen.
    $version = (Select-String -LiteralPath (Join-Path $gamePath 'project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
    $presetsPath = Join-Path $gamePath 'export_presets.cfg'
    $preset = Select-String -LiteralPath $presetsPath -Pattern '^version/name="(.+)"'
    if ($preset.Matches[0].Groups[1].Value -ne $version) { throw "Version in project.godot ($version) und Exportprofil unterscheiden sich." }
    $versionCode = Get-VersionCode $version
    $presetText = [IO.File]::ReadAllText($presetsPath)
    $codeLines = [regex]::Matches($presetText, '(?m)^version/code=(\d+)(\r?)$')
    if ($codeLines.Count -ne 1) { throw "Exportprofil: genau eine Zeile version/code erwartet, gefunden $($codeLines.Count)." }
    $presetCode = [long]$codeLines[0].Groups[1].Value
    if ($presetCode -gt $versionCode) {
        throw "version/code im Exportprofil ($presetCode) ist höher als der aus Version $version berechnete ($versionCode). Ein Update muss immer höher nummeriert sein – die Version anheben statt den Code zu senken."
    }
    if ($presetCode -ne $versionCode) {
        $presetText = $presetText.Remove($codeLines[0].Index, $codeLines[0].Length).Insert($codeLines[0].Index, "version/code=$versionCode$($codeLines[0].Groups[2].Value)")
        [IO.File]::WriteAllText($presetsPath, $presetText)
        Write-Output "Exportprofil: version/code $presetCode -> $versionCode (aus Version $version)"
    }
}
# Godot-Läufe des Projekts laufen nie gleichzeitig (mehrere Agenten teilen game/.godot und game/dioramas): benannter Systemmutex,
# derselbe wie in godot_run.ps1 und dio_build.ps1. Der Bau hält ihn von der ersten bis zur letzten Godot-Ausführung, damit zwischen
# Import, Importanpassung und Tests kein fremder Import dazwischenfährt.
$lock = New-Object System.Threading.Mutex($false, 'Global\Draw2RaceGodot')
$held = $false
try {
    try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $held = $true }    # Vorbesitzer abgestürzt: die Sperre gilt als erworben
    if (-not $held) { throw "Godot-Sperre (Global\Draw2RaceGodot) nach $LockWaitMinutes min nicht frei" }
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
    # Texturen, die Shader direkt abtasten (Bausatz der Diorama-Häuser tools/make_kit_textures.py, Rennausstattung, Boden-Sets
    # assets/ground, Themen-Texturen assets/dio/<thema>): in 3D brauchen sie Mipmaps; Grafikkartenkompression spart Speicher.
    # PNG und JPG; Normalkarten heißen <name>_n. (Dieselbe Anpassung macht tools/dio_build.ps1 nach einem einzelnen Diorama.)
    $textureFolders = @('assets/kit', 'assets/event', 'assets/ground', 'assets/dio') | ForEach-Object { Join-Path $gamePath $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $kit = @($textureFolders | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File } |
        Where-Object { $_.Name -like '*.png.import' -or $_.Name -like '*.jpg.import' } |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^mipmaps/generate=false\r?$' })
    if ($kit) {
        foreach ($file in $kit) {
            $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^mipmaps/generate=false(\r?)$', 'mipmaps/generate=true$1' -replace '(?m)^compress/mode=0(\r?)$', 'compress/mode=2$1' -replace '(?m)^compress/high_quality=false(\r?)$', 'compress/high_quality=true$1'
            if ($file.Name -like '*_n.png.import' -or $file.Name -like '*_n.jpg.import') { $text = $text -replace '(?m)^compress/normal_map=0(\r?)$', 'compress/normal_map=1$1' }
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
    # Alle Testläufe laufen immer durch (auch wenn einer scheitert), danach folgen eine Zusammenfassung je Lauf und ein Abbruch,
    # falls einer fehlgeschlagen ist. Ein Lauf gilt als bestanden mit Exitcode 0, ohne Fehlermuster (SCRIPT ERROR, ERROR:, FAIL:) und
    # mit RESULT-Zeile (--quit-after beendet ohne Fehler, wenn der Rahmenvorrat 180 vor dem Testende aufgebraucht ist).
    $suites = @()
    foreach ($test in @('test_core','test_flow','test_tracks','test_air','test_diorama','test_collision','test_heights','test_field','test_wear','test_multi','test_net','test_tags','test_party','test_lobby','test_draw','test_race','test_music','test_loading','test_apk')) {
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'      # Zeilen auf stderr (printerr der Tests, Warnungen) brechen nicht ab; entschieden wird unten
        try { $result = @(& $engine @('--headless','--path',$gamePath,'--quit-after','180','--script',"res://tests/$test.gd") 2>&1 | ForEach-Object { "$_" }) }
        finally { $ErrorActionPreference = $previousPreference }
        $exitCode = $LASTEXITCODE
        $result | Write-Output
        $failLines = @($result | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR:|FAIL:' })
        $resultLine = @($result | Where-Object { $_ -match 'RESULT: ' }) | Select-Object -Last 1
        $problem = ''
        if ($exitCode -ne 0) { $problem = "Exitcode $exitCode" }
        elseif (-not $resultLine) { $problem = 'keine RESULT-Zeile (abgebrochen?)' }
        elseif ($failLines.Count -gt 0) { $problem = "$($failLines.Count) Fehlerzeile(n)" }
        $suites += [pscustomobject]@{ Name = $test; Ok = ($problem -eq ''); Problem = $problem; Result = "$resultLine".Trim(); Failures = $failLines }
    }
    Write-Output ''
    Write-Output 'Zusammenfassung der Testläufe:'
    foreach ($suite in $suites) {
        $status = if ($suite.Ok) { 'OK     ' } else { 'FEHLER ' }
        Write-Output ("  {0} {1,-14} {2}{3}" -f $status, $suite.Name, $suite.Result, $(if ($suite.Problem) { "  [$($suite.Problem)]" } else { '' }))
        foreach ($line in ($suite.Failures | Select-Object -First 5)) { Write-Output ("            {0}" -f $line) }
    }
    $failedSuites = @($suites | Where-Object { -not $_.Ok })
    if ($failedSuites.Count -gt 0) { throw ("{0} von {1} Testläufen fehlgeschlagen: {2}" -f $failedSuites.Count, $suites.Count, (($failedSuites | ForEach-Object { $_.Name }) -join ', ')) }
    Write-Output ("Alle {0} Testläufe bestanden." -f $suites.Count)
    if ($Target -ne 'Test') {
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
            # Fester Projekt-Debugschlüssel (Vorabprüfung oben): Updates auf dem Gerät bleiben möglich, auch wenn %APPDATA%\Godot neu entsteht.
            $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $keystore
            $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = 'androiddebugkey'
            $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = 'android'
            $apk = Join-Path $projectRoot 'builds/Draw2Race.apk'
            Invoke-Godot -Arguments @('--headless','--path',$gamePath,'--export-debug','Android',$apk)
            # Signatur der fertigen APK nachprüfen: genau ein Unterzeichner, und zwar der Projektschlüssel. Erst dann entsteht die Release-Datei.
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'      # Warnungen von apksigner auf stderr brechen nicht ab; entschieden wird unten
            try { $certs = @(& (Find-ApkSigner) verify --print-certs $apk 2>&1 | ForEach-Object { "$_" }) }
            finally { $ErrorActionPreference = $previousPreference }
            if ($LASTEXITCODE -ne 0) { throw ("apksigner: Signatur der APK ungültig.`n" + ($certs -join "`n")) }
            $signers = @($certs | Where-Object { $_ -match 'certificate SHA-256 digest: ([0-9a-f]{64})' } | ForEach-Object { ($_ -split ': ')[-1].Trim() })
            if ($signers.Count -ne 1 -or $signers[0] -ne $projectCertSha256) {
                throw ("APK ist nicht mit dem Projektschlüssel signiert (gefunden: $($signers -join ', ')). In-App-Updates würden auf den Handys " +
                    "mit 'Signatur passt nicht' scheitern. .tools/draw2race-debug.keystore prüfen; builds/Draw2Race-$version.apk wurde nicht angelegt.")
            }
            Write-Output "APK-Signatur: Projektschlüssel (SHA-256 $($projectCertSha256.Substring(0, 16))...), version/code $versionCode"
            # Release-Datei für GitHub: Die Update-Funktion erwartet genau "Draw2Race-<version>.apk" (version = config/version).
            Copy-Item -LiteralPath $apk -Destination (Join-Path $projectRoot "builds/Draw2Race-$version.apk") -Force
        }
        Copy-Item -LiteralPath (Join-Path $gamePath 'assets/OFL.txt') -Destination (Join-Path $projectRoot 'builds/Outfit-LICENSE.txt') -Force
        Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-LICENSE.txt') -Destination (Join-Path $projectRoot 'builds/Godot-LICENSE.txt') -Force
        Copy-Item -LiteralPath (Join-Path $gamePath 'assets/Godot-COPYRIGHT.txt') -Destination (Join-Path $projectRoot 'builds/Godot-COPYRIGHT.txt') -Force
    }
}
finally {
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
