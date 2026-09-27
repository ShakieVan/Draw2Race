# Startet ein Blender-Python-Skript im Hintergrund, isoliert: Benutzerdaten und Temp-Dateien liegen in
# .tools/blender (nicht im Windows-Profil). Blender selbst wird nicht installiert; verwendet wird eine
# vorhandene portable Kopie (Pfad über DRAW2RACE_BLENDER oder .tools/blender_path.txt).
param(
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$ScriptArgs
)
$ErrorActionPreference = 'Stop'
$Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Blender = $env:DRAW2RACE_BLENDER
# Lokaler Standardpfad (nicht im Repo): .tools/blender_path.txt
$PathFile = Join-Path $Project '.tools/blender_path.txt'
if (-not $Blender -and (Test-Path -LiteralPath $PathFile)) { $Blender = (Get-Content -LiteralPath $PathFile -Raw).Trim() }
if (-not $Blender) { throw 'Blender-Pfad fehlt: DRAW2RACE_BLENDER setzen oder .tools/blender_path.txt anlegen' }
if (-not (Test-Path -LiteralPath $Blender)) { throw "Blender nicht gefunden: $Blender (DRAW2RACE_BLENDER setzen)" }
$State = Join-Path $Project '.tools/blender'
$Names = @('BLENDER_USER_RESOURCES', 'TEMP', 'TMP', 'PYTHONDONTWRITEBYTECODE')
$Old = @{}
foreach ($Name in $Names) { $Old[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process') }
try {
    $env:BLENDER_USER_RESOURCES = Join-Path $State 'user'
    $env:TEMP = Join-Path $State 'temp'
    $env:TMP = $env:TEMP
    $env:PYTHONDONTWRITEBYTECODE = '1'
    New-Item -ItemType Directory -Force -Path $env:BLENDER_USER_RESOURCES, $env:TEMP | Out-Null
    & $Blender --background --factory-startup --disable-autoexec --offline-mode --python-exit-code 1 --python $Script -- @ScriptArgs
    $Code = $LASTEXITCODE
} finally {
    foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $Old[$Name], 'Process') }
}
exit $Code
