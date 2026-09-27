# Bereitet alle KI-Kulissenmodelle (.tools/ai3d/runs/<name>) für das Spiel auf: game/assets/props/<name>.glb.
# Budgets: viele gleiche Objekte (Bäume, Laternen) knapp, einzelne große (Häuser) großzügiger.
param([string[]]$Only)
$ErrorActionPreference = 'Stop'
if ($Only) { $Only = @($Only | ForEach-Object { $_ -split ',' }) }
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$Budget = @{
    'wald_kiefer' = @(9000, 512); 'wald_eiche' = @(10000, 512); 'wald_busch' = @(1500, 512); 'kueste_palme' = @(3000, 512)
    'stadt_baum' = @(2500, 512); 'stadt_laterne' = @(800, 256); 'wald_laterne' = @(1200, 256); 'kueste_laterne' = @(1500, 256)
    'kueste_flutlicht' = @(2500, 512); 'kueste_felsen' = @(2000, 512); 'wald_felsen' = @(2000, 512)
    'stadt_altbau' = @(9000, 1024); 'stadt_eckladen' = @(9000, 1024); 'stadt_wohnblock' = @(8000, 1024); 'stadt_buero' = @(6000, 1024)
    'kueste_clubhaus' = @(9000, 1024); 'kueste_tribuene' = @(12000, 1024); 'kueste_bootshaus' = @(8000, 1024); 'wald_huette' = @(8000, 1024)
    'kueste_zeitnahme' = @(6000, 1024)
}
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'game/assets/props') | Out-Null
foreach ($Dir in Get-ChildItem (Join-Path $Root '.tools/ai3d/runs') -Directory) {
    $Name = $Dir.Name
    if ($Name.StartsWith('auto_')) { continue }
    if ($Only -and -not ($Only -contains $Name)) { continue }
    $Src = Join-Path $Dir.FullName 'model.glb'
    if (-not (Test-Path $Src)) { continue }
    $B = $Budget[$Name]
    if (-not $B) { $B = @(4000, 512) }
    $Dst = Join-Path $Root "game/assets/props/$Name.glb"
    & (Join-Path $PSScriptRoot 'blender.ps1') (Join-Path $PSScriptRoot 'ai_prop.py') $Src $Dst $B[0] $B[1] | Select-String 'AIPROP|Error|Traceback'
}
