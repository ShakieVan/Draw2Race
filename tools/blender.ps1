# Startet ein Blender-Python-Skript im Hintergrund, isoliert: Benutzerdaten und Temp-Dateien liegen in
# .tools/blender (nicht im Windows-Profil). Blender selbst wird nicht installiert; verwendet wird eine
# vorhandene portable Kopie (Pfad über DRAW2RACE_BLENDER überschreibbar).
param(
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(ValueFromRemainingArguments=$true)][string[]]$ScriptArgs
)
$ErrorActionPreference = 'Stop'
$Project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Blender = $env:DRAW2RACE_BLENDER
if (-not $Blender) { $Blender = 'C:\Users\Shakie\Documents\Lood-Ball\tools\blender\blender-4.5.13-windows-x64\blender.exe' }
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
