# Baut alle KI-Autos aus den TRELLIS-Ergebnissen (.tools/ai3d/runs) nach game/assets/cars (Einstellungen: ai_cars.json).
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Config = Get-Content (Join-Path $PSScriptRoot 'ai_cars.json') -Raw | ConvertFrom-Json
foreach ($Entry in $Config.PSObject.Properties) {
    if ($Entry.Name.StartsWith('_')) { continue }
    $Src = Join-Path $Root ".tools/ai3d/runs/$($Entry.Name)/model.glb"
    if (-not (Test-Path $Src)) { Write-Host "fehlt: $Src"; continue }
    $Dst = Join-Path $Root "game/assets/cars/$($Entry.Value.style).glb"
    $Extra = @()
    if ($Entry.Value.radius) { $Extra += @('--radius', "$($Entry.Value.radius)") }
    & (Join-Path $PSScriptRoot 'blender.ps1') (Join-Path $PSScriptRoot 'ai_car.py') $Src $Dst $Entry.Value.style @Extra --preview (Join-Path $Root '.tools/cars/ai') | Select-String 'AICAR|Error|Traceback'
}
