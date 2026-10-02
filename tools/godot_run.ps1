param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$Timeout = 90,
    [string]$Resolution = '1600x900',
    [string[]]$EnvPairs = @(),
    [string[]]$Extra = @(),
    [switch]$Headless,
    [int]$LockWaitMinutes = 60
)
# Startet ein Godot-Testskript aus game/tests mit Zeitgrenze und gibt die Ausgabe zurück. Bei einem Skriptfehler innerhalb einer
# Coroutine bleibt Godot sonst offen. Umgebungsvariablen der Skripte (TRACK, TIME, WEATHER …) als "NAME=Wert" in -EnvPairs.
# Beispiel:  tools/godot_run.ps1 -Script res://tests/dio_shot.gd -EnvPairs 'TRACK=city','TIME=night'
# (aus der PowerShell heraus aufrufen, nicht über "powershell -File": dort kommt -EnvPairs als eine Zeichenkette an)
# Weitere Godot-Argumente in -Extra, z. B. -Extra '--audio-driver','Dummy' (Tonaufnahme ohne Lautsprecher).
# Godot-Läufe des Projekts laufen nie gleichzeitig: Alle Skripte (godot_run, build, dio_build) halten dazu den benannten
# Systemmutex Global\Draw2RaceGodot (mehrere Agenten teilen game/.godot, game/dioramas und die Importe). Innerhalb desselben Prozesses
# ist die Sperre wiederholt nehmbar (dio_build ruft godot_run auf).
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\Godot_v4.6.1-stable_win64_console.exe'
$lock = New-Object System.Threading.Mutex($false, 'Global\Draw2RaceGodot')
$held = $false
try {
    try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $held = $true }    # Vorbesitzer abgestürzt: die Sperre gilt als erworben
    if (-not $held) { throw "Godot-Sperre (Global\Draw2RaceGodot) nach $LockWaitMinutes min nicht frei" }
    foreach ($p in $EnvPairs) { $k, $v = $p.Split('=', 2); Set-Item -Path "Env:$k" -Value $v }
    $out = Join-Path $env:TEMP ("godot_run_" + [guid]::NewGuid().ToString('N') + '.txt')
    $err = $out + '.err'
    $arguments = @('--path', (Join-Path $root 'game'))
    if ($Headless) { $arguments += '--headless' } else { $arguments += @('--resolution', $Resolution) }
    $arguments += $Extra
    $arguments += @('--script', $Script)
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $proc.WaitForExit($Timeout * 1000)) {
        Write-Output "ZEITGRENZE nach $Timeout s - Prozess beendet"
        # nur den eigenen Prozess samt Kindern beenden (nicht jedes Godot: Editor und Läufe anderer bleiben unberührt)
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Content $out -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^(Godot Engine|Vulkan)' -and $_.Trim() -ne '' }
    Get-Content $err -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' } | Select-Object -First 20
    Remove-Item $out, $err -ErrorAction SilentlyContinue
}
finally {
    foreach ($p in $EnvPairs) { $k = $p.Split('=', 2)[0]; Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
