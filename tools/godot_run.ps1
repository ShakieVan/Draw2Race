param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$Timeout = 90,
    [string]$Resolution = '1600x900',
    [string[]]$EnvPairs = @(),
    [switch]$Headless
)
# Startet ein Godot-Testskript aus game/tests mit Zeitgrenze und gibt die Ausgabe zurück. Bei einem Skriptfehler innerhalb einer
# Coroutine bleibt Godot sonst offen. Umgebungsvariablen der Skripte (TRACK, TIME, WEATHER …) als "NAME=Wert" in -EnvPairs.
# Beispiel:  tools/godot_run.ps1 -Script res://tests/dio_shot.gd -EnvPairs 'TRACK=city','TIME=night'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\Godot_v4.6.1-stable_win64_console.exe'
foreach ($p in $EnvPairs) { $k, $v = $p.Split('=', 2); Set-Item -Path "Env:$k" -Value $v }
$out = Join-Path $env:TEMP ("godot_run_" + [guid]::NewGuid().ToString('N') + '.txt')
$err = $out + '.err'
$arguments = @('--path', (Join-Path $root 'game'))
if ($Headless) { $arguments += '--headless' } else { $arguments += @('--resolution', $Resolution) }
$arguments += @('--script', $Script)
$proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
if (-not $proc.WaitForExit($Timeout * 1000)) {
    Write-Output "ZEITGRENZE nach $Timeout s - Prozess beendet"
    Stop-Process -Id $proc.Id -Force
    Get-Process | Where-Object { $_.ProcessName -like 'Godot*' } | Stop-Process -Force -ErrorAction SilentlyContinue
}
Get-Content $out -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^(Godot Engine|Vulkan)' -and $_.Trim() -ne '' }
Get-Content $err -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' } | Select-Object -First 20
Remove-Item $out, $err -ErrorAction SilentlyContinue
foreach ($p in $EnvPairs) { $k = $p.Split('=', 2)[0]; Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
