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
    'hafen_lagerhalle' = @(10000, 1024); 'hafen_frachtschiff' = @(10000, 1024); 'hafen_kran' = @(6000, 1024); 'hafen_laterne' = @(1200, 256)
    'hafen_poller' = @(600, 256); 'hafen_container' = @(1500, 512); 'hafen_faesser' = @(1500, 512); 'hafen_paletten' = @(1200, 512)
    'jahrmarkt_riesenrad' = @(10000, 1024); 'jahrmarkt_karussell' = @(8000, 1024); 'jahrmarkt_zelt' = @(6000, 1024); 'jahrmarkt_lichtermast' = @(1200, 256)
    'jahrmarkt_autoscooter' = @(8000, 1024); 'jahrmarkt_bude' = @(4000, 512); 'jahrmarkt_losbude' = @(4000, 512); 'jahrmarkt_bruecke' = @(4000, 512)
    'serra_kapelle' = @(8000, 1024); 'serra_leuchtturm' = @(6000, 1024); 'serra_agave' = @(1500, 512); 'serra_leitplanke' = @(2000, 512)
    'serra_trockenmauer' = @(2500, 512); 'serra_olivenbaum' = @(3000, 512); 'serra_pinie' = @(3000, 512); 'serra_fels' = @(2000, 512)
    'steinbruch_brecher' = @(8000, 1024); 'steinbruch_bagger' = @(6000, 1024); 'steinbruch_kipper' = @(6000, 1024); 'steinbruch_buero' = @(6000, 1024)
    'steinbruch_felswand' = @(4000, 1024); 'steinbruch_kieshaufen' = @(2000, 512); 'steinbruch_foerderband' = @(4000, 512)
    'drift_parkhaus' = @(9000, 1024); 'drift_zuschauer_container' = @(6000, 1024); 'drift_betonblock' = @(800, 256); 'drift_reifenwand' = @(2000, 512)
    'drift_pylone' = @(600, 256); 'drift_zaun' = @(1500, 512); 'drift_flutlicht' = @(2500, 512)
    'kinder_teddy' = @(8000, 1024); 'kinder_holzeisenbahn' = @(6000, 1024); 'kinder_bausteinturm' = @(4000, 1024); 'kinder_bauklotz' = @(800, 256)
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
    # Vereinfachte Fassung (<name>_lo.glb) für Schatten und Übersicht: ~1/6 der Dreiecke, halbe Textur.
    if ($B[0] -ge 2500) {
        $Lo = Join-Path $Root "game/assets/props/${Name}_lo.glb"
        $LoTris = [Math]::Max(600, [int]($B[0] / 6))
        & (Join-Path $PSScriptRoot 'blender.ps1') (Join-Path $PSScriptRoot 'ai_prop.py') $Src $Lo $LoTris ([Math]::Max(256, [int]($B[1] / 2))) | Select-String 'AIPROP|Error|Traceback'
    }
}
