param(
    [Parameter(Mandatory = $true)][string]$Track,
    [switch]$Shots,
    [string[]]$Times = @('day'),
    [string]$Tag = '',
    [string]$ThemeFile = '',
    [int]$LockWaitMinutes = 120
)
# Baut das Diorama einer Strecke und bringt es ins Spiel (docs/dioramen/README.md):
#   1. Blender (tools/diorama.py) erzeugt <id>.glb, <id>_ao.jpg, <id>_layout.json, <id>_recipe.json in .tools/dio_tmp/<id>/
#      (parallel zu anderen Agenten möglich: jede Strecke hat ihren eigenen Ordner)
#   2. unter der gemeinsamen Godot-Sperre (Global\Draw2RaceGodot): Ausgaben nach game/dioramas/ verschieben, Godot-Import,
#      Importanpassungen (WebP für extrahierte Modelltexturen; Mipmaps und Grafikkartenkompression für assets/ground und assets/dio),
#      bei Änderungen erneuter Import
#   3. mit -Shots: Kontrollbilder je Tageszeit (tests/dio_shot.gd): Übersicht und Nahansicht als PNG
# Beispiel:  tools/dio_build.ps1 -Track harbor -Shots -Times day,night -Tag _v1
# -ThemeFile nimmt ein Themenmodul von Hand statt tools/dio_themes/<thema>.py (Versuche). Aufruf aus der PowerShell, nicht über
# "powershell -File" mit Listen (dort kommt -Times als eine Zeichenkette an; sie wird hier an Kommas geteilt).
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/Godot_v4.6.1-stable_win64_console.exe'
$gamePath = Join-Path $projectRoot 'game'
$trackJson = Join-Path $gamePath "tracks/$Track.json"
if (-not (Test-Path -LiteralPath $trackJson)) { throw "Streckendatei fehlt: $trackJson" }
if (-not (Test-Path -LiteralPath $engine)) { throw 'Godot 4.6.1 fehlt. Zuerst tools/setup.ps1 ausführen.' }
$Times = @($Times | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
foreach ($t in $Times) { if ($t -notin @('day', 'dusk', 'night')) { throw "Unbekannte Tageszeit: $t (day, dusk, night)" } }
$theme = (Get-Content -LiteralPath $trackJson -Raw -Encoding UTF8 | ConvertFrom-Json).theme
$themeModule = if ($ThemeFile) { $ThemeFile } else { Join-Path $PSScriptRoot "dio_themes/$theme.py" }
Write-Output ("Strecke {0}, Thema {1}, Themenmodul: {2}" -f $Track, $theme, $(if (Test-Path -LiteralPath $themeModule) { $themeModule } else { 'keines (nur Kern)' }))

# --- 1. Blender
$tmp = Join-Path $projectRoot ".tools/dio_tmp/$Track"
New-Item -ItemType Directory -Force $tmp | Out-Null
$names = @("$Track.glb", "${Track}_ao.jpg", "${Track}_layout.json", "${Track}_recipe.json")
foreach ($n in $names) { Remove-Item -LiteralPath (Join-Path $tmp $n) -ErrorAction SilentlyContinue }
$log = Join-Path $tmp 'blender.log'
$blenderArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f (Join-Path $PSScriptRoot 'blender.ps1')),
    ('"{0}"' -f (Join-Path $PSScriptRoot 'diorama.py')), ('"{0}"' -f $trackJson), ('"{0}"' -f (Join-Path $tmp "$Track.glb")),
    ('"{0}"' -f (Join-Path $tmp "${Track}_ao.jpg")), ('"{0}"' -f (Join-Path $projectRoot 'art/texturen')),
    ('"{0}"' -f (Join-Path $gamePath 'assets/props')))
if ($ThemeFile) { $blenderArgs += ('"{0}"' -f (Resolve-Path -LiteralPath $ThemeFile).Path) }
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
# Blender backt die Lichttextur auf der Grafikkarte (je ~1-2 GB); auf beiden Karten ist meist nur wenig Speicher frei (KI-Modelle
# der Werkstatt). Deshalb läuft auch Blender nie parallel: eigene Sperre Global\Draw2RaceBlender (getrennt von der Godot-Sperre).
$blenderLock = New-Object System.Threading.Mutex($false, 'Global\Draw2RaceBlender')
$blenderHeld = $false
try {
    try { $blenderHeld = $blenderLock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $blenderHeld = $true }
    if (-not $blenderHeld) { throw "Blender-Sperre (Global\Draw2RaceBlender) nach $LockWaitMinutes min nicht frei" }
    $stopwatch.Restart()
    $blender = Start-Process -FilePath 'powershell.exe' -ArgumentList $blenderArgs -PassThru -NoNewWindow -Wait -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
}
finally {
    if ($blenderHeld) { $blenderLock.ReleaseMutex() }
    $blenderLock.Dispose()
}
Write-Output ("Blender: Exit {0}, {1:n0} s, Protokoll {2}" -f $blender.ExitCode, $stopwatch.Elapsed.TotalSeconds, $log)
Get-Content -LiteralPath $log -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^DIORAMA|Traceback|Error|GPU nicht' } | Select-Object -First 60
if ($blender.ExitCode -ne 0) {
    Get-Content -LiteralPath ($log + '.err') -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -Last 30
    throw "Blender fehlgeschlagen (Exit $($blender.ExitCode)); game/dioramas bleibt unverändert."
}
foreach ($n in $names) {
    $f = Join-Path $tmp $n
    if (-not (Test-Path -LiteralPath $f) -or (Get-Item -LiteralPath $f).Length -eq 0) { throw "Blender hat $n nicht erzeugt." }
}

# --- 2. Übernahme und Import unter der Godot-Sperre
function Invoke-Godot([string[]]$Arguments) {
    # Ausgabe nur bei Fehlern (der Import schreibt sehr viel); Fehlererkennung wie in build.ps1. Zeilen auf stderr (Warnungen,
    # z. B. "glTF file has no nodes") brechen nicht ab: entschieden wird am Exitcode und an den Fehlermustern.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $engine @Arguments 2>&1 | ForEach-Object { "$_" }) } finally { $ErrorActionPreference = $previous }
    if ($LASTEXITCODE -ne 0 -or ($output -match 'SCRIPT ERROR|^ERROR:|FAIL:')) {
        $output | Write-Output
        throw "Godot fehlgeschlagen: $Arguments"
    }
}
$importArgs = @('--headless', '--path', $gamePath, '--editor', '--import', '--quit')
$lock = New-Object System.Threading.Mutex($false, 'Global\Draw2RaceGodot')
$held = $false
try {
    try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $held = $true }    # Vorbesitzer abgestürzt: die Sperre gilt als erworben
    if (-not $held) { throw "Godot-Sperre (Global\Draw2RaceGodot) nach $LockWaitMinutes min nicht frei" }
    foreach ($n in $names) { Copy-Item -LiteralPath (Join-Path $tmp $n) -Destination (Join-Path $gamePath "dioramas/$n") -Force }
    Write-Output "Ausgaben nach game/dioramas/ übernommen"
    Invoke-Godot -Arguments $importArgs | Out-Null
    # Von Godot neben die .glb gelegte Modelltexturen (<id>_*.jpg): verlustfrei importiert blähen sie die APK auf -> WebP (wie build.ps1).
    $lossless = @(Get-ChildItem (Join-Path $gamePath 'dioramas') -Filter '*.jpg.import' |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^compress/mode=0\r?$' })
    foreach ($file in $lossless) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^compress/mode=0(\r?)$', 'compress/mode=1$1' -replace '(?m)^compress/lossy_quality=0\.7(\r?)$', 'compress/lossy_quality=0.8$1'
        [IO.File]::WriteAllText($file.FullName, $text)
    }
    # Texturen, die Shader direkt abtasten (Bausatz, Rennausstattung, Boden-Sets, Themen-Texturen assets/dio/<thema>): Mipmaps und
    # Grafikkartenkompression, PNG und JPG; Normalkarten heißen <name>_n (wie build.ps1).
    $textureFolders = @('assets/kit', 'assets/event', 'assets/ground', 'assets/dio') | ForEach-Object { Join-Path $gamePath $_ } | Where-Object { Test-Path -LiteralPath $_ }
    $kit = @($textureFolders | ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -File } |
        Where-Object { $_.Name -like '*.png.import' -or $_.Name -like '*.jpg.import' } |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?m)^mipmaps/generate=false\r?$' })
    foreach ($file in $kit) {
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace '(?m)^mipmaps/generate=false(\r?)$', 'mipmaps/generate=true$1' -replace '(?m)^compress/mode=0(\r?)$', 'compress/mode=2$1' -replace '(?m)^compress/high_quality=false(\r?)$', 'compress/high_quality=true$1'
        if ($file.Name -like '*_n.png.import' -or $file.Name -like '*_n.jpg.import') { $text = $text -replace '(?m)^compress/normal_map=0(\r?)$', 'compress/normal_map=1$1' }
        [IO.File]::WriteAllText($file.FullName, $text)
    }
    if ($lossless.Count -gt 0 -or $kit.Count -gt 0) {
        Write-Output ("Importanpassungen: {0} Modelltexturen auf WebP, {1} Shader-Texturen mit Mipmaps/Kompression" -f $lossless.Count, $kit.Count)
        Invoke-Godot -Arguments $importArgs | Out-Null
    }

    # --- 3. Kontrollbilder
    $userdir = Join-Path $env:APPDATA 'Godot/app_userdata/Draw2Race'
    $images = @()
    if ($Shots) {
        foreach ($t in $Times) {
            $started = Get-Date
            & (Join-Path $PSScriptRoot 'godot_run.ps1') -Script 'res://tests/dio_shot.gd' -EnvPairs "TRACK=$Track", "TIME=$t", "TAG=$Tag" -Timeout 240
            foreach ($kind in @('uebersicht', 'nah')) {
                $png = Join-Path $userdir ("dio_{0}_{1}{2}_{3}.png" -f $Track, $t, $Tag, $kind)
                if ((Test-Path -LiteralPath $png) -and (Get-Item -LiteralPath $png).LastWriteTime -ge $started.AddSeconds(-2)) { $images += $png }
                else { Write-Warning "Kontrollbild fehlt oder ist alt: $png" }
            }
        }
    }
}
finally {
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}

# --- Ergebnis
Write-Output ''
Write-Output 'Ausgaben:'
foreach ($n in $names) { $f = Get-Item -LiteralPath (Join-Path $gamePath "dioramas/$n"); Write-Output ("  {0}  ({1:n0} KB)" -f $f.FullName, ($f.Length / 1KB)) }
$layout = Get-Content -LiteralPath (Join-Path $gamePath "dioramas/${Track}_layout.json") -Raw | ConvertFrom-Json
Write-Output ("Begleitdatei: Hindernisse {0}, Straßenflächen {1}, Laternen {2}, runtime_road {3}, runtime_terrain {4}" -f @($layout.obstacles).Count, @($layout.blocked).Count, @($layout.lamps).Count, [bool]$layout.runtime_road, [bool]$layout.runtime_terrain)
if ($images.Count -gt 0) {
    Write-Output 'Kontrollbilder:'
    $images | ForEach-Object { Write-Output "  $_" }
}
