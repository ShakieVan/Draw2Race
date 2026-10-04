param(
    [int]$Clients = 3,
    [int]$Timeout = 40,
    [string]$Address = '',
    [switch]$Reject,
    [switch]$Search,
    [switch]$Lobby,
    [switch]$Apk,
    [int]$Duration = 4,
    [double]$Speed = 1.0,
    [double]$Drop = 0.1
)
# Netztest am PC (docs/MULTIPLAYER_RECHERCHE.md, Meilenstein M0): startet einen Host und mehrere Mitspieler als getrennte
# Godot-Prozesse (headless, game/scripts/net/net_cli.gd) und wertet ihre Ergebniszeilen aus.
#   Mitspieler 1 sucht den Host (Rundruf, Netz-Rundruf, Ankündigung), Mitspieler 2 verbindet über 127.0.0.1, Mitspieler 3 über die
#   LAN-Adresse dieses PCs (-Address, sonst die Adresse am Standard-Gateway), weitere suchen wieder.
#   -Reject: zusätzlich ein Mitspieler mit falscher Spielversion – seine Ablehnung ist das erwartete Ergebnis.
#   -Search: zusätzlich ein reiner Suchlauf (meldet alle Fundwege).
# Bewusst OHNE die Godot-Sperre Global\Draw2RaceGodot (tools/godot_run.ps1): Host und Mitspieler müssen gleichzeitig laufen. Die Läufe
# importieren nichts und schreiben nur ihre Protokolle nach %APPDATA%\Godot\app_userdata\Draw2Race\netztest_*.log.
#   -Lobby: Lobby-Szenario (M3, game/scripts/net/lobby_cli.gd) statt des Ping-Tests: Host + Mitspieler (Wege wie oben) treten der
#   Lobby bei, der Host stellt ein, alle melden sich bereit, Start, gemeinsames Laden, gemeinsames Zeichnen mit Bot-Linien (M4: alle
#   Linien müssen bei allen dieselbe Prüfsumme haben), der Host beendet; dazu je ein Mitspieler mit falschen Streckendaten und mit
#   falscher Spielversion (Ablehnung erwartet). Schreibt keine Protokolldateien.
#   Seit M5 geht es weiter bis zur Wertung: Der Host rechnet das Rennen, alle zeigen es aus den Schnappschüssen und drücken den Turbo
#   nach Plan; Mitspieler 1 verwirft dabei absichtlich -Drop (10 %) der Schnappschüsse. Geprüft wird: Wertung und Simulation bei allen
#   gleich (wertung=, sim=; Autowahl: alle im selben Auto, Spielerfarben eindeutig und überall gleich, farben=), der Host rechnet bitgleich wie RaceField ohne Netz (nachgerechnet=ja), keine Sprünge in der Anzeige.
#   -Speed: Zeitraffer des Rennens (1 = Echtzeit). Lobby-Läufe brauchen in Echtzeit gut eine Minute (-Timeout ab 120 s).
#   -Apk: Weitergabe der neueren Version (game/tests/apk_cli.gd, NetApk): ein Gastgeber mit 40-MB-Testdatei (gedrosselt auf 20 MB/s),
#   ein älterer Mitspieler holt sie und prüft sie gegen die Quelle, ein zweiter bricht nach 8 MB ab, ein neuerer Mitspieler gibt dem
#   Gastgeber seine Version; ein zweiter Gastgeber verfälscht ein Byte, sein Mitspieler muss die Datei ablehnen. Jeder misst den
#   längsten Bildabstand während der Übertragung (Grenze 50 ms).
# Aufruf: powershell -NoProfile -ExecutionPolicy Bypass -File tools/net_test.ps1 [-Clients 3] [-Reject] [-Search] [-Lobby [-Speed 1] [-Drop 0.1]] [-Apk]
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\Godot_v4.6.1-stable_win64_console.exe'
if (-not (Test-Path -LiteralPath $exe)) { throw 'Godot 4.6.1 fehlt. Zuerst tools/setup.ps1 ausführen.' }
$game = Join-Path $root 'game'
if ($Address -eq '') {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
    if ($route) {
        $Address = (Get-NetIPAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress
    }
}
$runs = @()
function Start-NetRun([string]$Name, [string[]]$UserArgs) {
    $out = Join-Path $env:TEMP ("draw2race_net_{0}_{1}.txt" -f $Name, [guid]::NewGuid().ToString('N'))
    if ($Apk) {
        $arguments = @('--headless', '--path', "`"$game`"", '--script', 'res://tests/apk_cli.gd', '--') + $UserArgs + @("--apktest-name=$Name")
    } elseif ($Lobby) {
        $arguments = @('--headless', '--path', "`"$game`"", '--script', 'res://scripts/net/lobby_cli.gd', '--') + $UserArgs + @("--lobbytest-name=$Name")
    } else {
        $arguments = @('--headless', '--path', "`"$game`"", '--script', 'res://scripts/net/net_cli.gd', '--') + $UserArgs +
            @("--nettest-log=user://netztest_$Name.log", "--nettest-name=$Name")
    }
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError ($out + '.err')
    $null = $proc.Handle    # Handle merken, sonst liefert ExitCode nach dem Ende nichts
    $script:runs += [pscustomobject]@{ Name = $Name; Proc = $proc; Out = $out; Args = ($UserArgs -join ' ') }
}
if ($Apk) {
    Write-Output 'APK-Weitergabe: Gastgeber + Holer + Abbrecher + Neuling, Fälscher + Opfer (127.0.0.1, eigene Ports 24710–24728)'
    Start-NetRun 'Quelle' @('--apktest=host', '--apktest-port=24710', '--apktest-mb=40', '--apktest-rate=20', '--apktest-served=1', '--apktest-aborted=1', '--apktest-pull', "--apktest-timeout=$Timeout")
    Start-NetRun 'Faelscher' @('--apktest=host', '--apktest-port=24720', '--apktest-mb=16', '--apktest-corrupt', '--apktest-served=1', "--apktest-timeout=$Timeout")
    Start-Sleep -Milliseconds 2500
    Start-NetRun 'Holer' @('--apktest=fetch', '--apktest-port=24710', '--apktest-source=Quelle', "--apktest-timeout=$([int]($Timeout - 5))")
    Start-NetRun 'Abbrecher' @('--apktest=fetch', '--apktest-port=24710', '--apktest-cancel=8', "--apktest-timeout=$([int]($Timeout - 5))")
    Start-NetRun 'Neuling' @('--apktest=give', '--apktest-port=24710', '--apktest-own-port=24718', '--apktest-mb=12', "--apktest-timeout=$([int]($Timeout - 5))")
    Start-NetRun 'Opfer' @('--apktest=fetch', '--apktest-port=24720', '--apktest-expect=Prüfsumme', "--apktest-timeout=$([int]($Timeout - 5))")
} elseif ($Lobby) {
    if (-not $PSBoundParameters.ContainsKey('Timeout')) { $Timeout = 150 }
    $speedArg = "--lobbytest-speed=$([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Speed))"
    Write-Output ("Lobbytest: 1 Host + {0} Mitspieler + 2 Ablehnungen (Streckendaten, Spielversion), LAN-Adresse {1}, Rennen im Zeitraffer {2}, Mitspieler 1 verwirft {3:P0} der Schnappschüsse" -f $Clients, $(if ($Address) { $Address } else { 'unbekannt' }), $Speed, $Drop)
    # Hänger wie auf langsamen Handys (gemessen 5,1 s beim Laden des Steinbruchs): Der Host steht beim Laden 5,2 s, Mitspieler 3 6 s –
    # niemand darf herausfliegen. Vorher meldet sich „Abmelder“ nach dem Beitritt sauber ab (beim Host: abgemeldet=1, ohne ERROR-Zeile).
    Start-NetRun 'Host' @('--lobbytest=host', "--lobbytest-expect=$Clients", "--lobbytest-timeout=$Timeout", $speedArg, '--lobbytest-stall=5.2')
    Start-Sleep -Milliseconds 1500
    Start-NetRun 'Streckendaten' @('--lobbytest=join:127.0.0.1', '--lobbytest-fake=track', '--lobbytest-timeout=15')
    Start-NetRun 'Altversion' @('--lobbytest=join:127.0.0.1', '--lobbytest-fake=version', '--lobbytest-timeout=15')
    Start-NetRun 'Abmelder' @('--lobbytest=join:127.0.0.1', '--lobbytest-leave=0.5', '--lobbytest-timeout=15')
    Start-Sleep -Milliseconds 3500
    for ($i = 1; $i -le $Clients; $i++) {
        $mode = '--lobbytest=join'
        if ($i -eq 2) { $mode = '--lobbytest=join:127.0.0.1' }
        elseif ($i -eq 3 -and $Address) { $mode = "--lobbytest=join:$Address" }
        $extra = @($speedArg)
        if ($i -eq 1 -and $Drop -gt 0) { $extra += "--lobbytest-drop=$([string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0}', $Drop))" }
        if ($i -eq 3) { $extra += '--lobbytest-stall=6' }
        # Autowahl: alle fahren dasselbe Auto und wünschen sich dieselbe Farbe (Orange) – der Gastgeber vergibt die Farben eindeutig.
        Start-NetRun "Mitspieler$i" (@($mode, "--lobbytest-timeout=$([int]($Timeout - 5))", '--lobbytest-car=0', '--lobbytest-color=4') + $extra)
        Start-Sleep -Milliseconds 300
    }
} else {
    Write-Output ("Netztest: 1 Host + {0} Mitspieler{1}{2}, LAN-Adresse {3}" -f $Clients, $(if ($Reject) { ' + 1 mit falscher Version' } else { '' }),
        $(if ($Search) { ' + Suchlauf' } else { '' }), $(if ($Address) { $Address } else { 'unbekannt' }))
    Start-NetRun 'Host' @('--nettest=host', "--nettest-expect=$Clients", "--nettest-timeout=$Timeout")
    Start-Sleep -Milliseconds 1500
    for ($i = 1; $i -le $Clients; $i++) {
        $mode = '--nettest=join'
        if ($i -eq 2) { $mode = '--nettest=join:127.0.0.1' }
        elseif ($i -eq 3 -and $Address) { $mode = "--nettest=join:$Address" }
        Start-NetRun "Mitspieler$i" @($mode, "--nettest-timeout=$([int]($Timeout - 5))", "--nettest-duration=$Duration")
        Start-Sleep -Milliseconds 300
    }
    if ($Reject) { Start-NetRun 'Altversion' @('--nettest=join:127.0.0.1', '--nettest-fake-version=0.0.1', '--nettest-timeout=15') }
    if ($Search) { Start-NetRun 'Suche' @('--nettest=search', '--nettest-timeout=15') }
}
$failed = 0
$digestSeen = @()
$rowsSeen = @()
$simSeen = @()
$colorsSeen = @()
$musicSeen = @()
foreach ($run in $runs) {
    if (-not $run.Proc.WaitForExit(($Timeout + 20) * 1000)) {
        Stop-Process -Id $run.Proc.Id -Force -ErrorAction SilentlyContinue
        Write-Output ("ZEITGRENZE: {0} beendet" -f $run.Name)
    }
}
Write-Output ''
foreach ($run in $runs) {
    $lines = @(Get-Content -LiteralPath $run.Out -Encoding UTF8 -ErrorAction SilentlyContinue)
    $errors = @(Get-Content -LiteralPath ($run.Out + '.err') -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
    $result = @($lines | Where-Object { $_ -match '(NETTEST|LOBBYTEST|APKTEST)-ERGEBNIS: ' }) | Select-Object -Last 1
    $ok = ($run.Proc.ExitCode -eq 0) -and ("$result" -match '(NETTEST|LOBBYTEST|APKTEST)-ERGEBNIS: OK') -and -not ($lines + $errors | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR:' })
    if ($Lobby -and $run.Name -eq 'Host' -and "$result" -notmatch 'abgemeldet=1 ') { $ok = $false; Write-Output 'FEHLER: Host hat die saubere Abmeldung nicht gesehen (abgemeldet=1 erwartet)' }
    if ($ok -and "$result" -match 'digest=([0-9a-f]+)') { $digestSeen += $Matches[1] }
    if ($ok -and "$result" -match 'wertung=([0-9a-f]+)') { $rowsSeen += $Matches[1] }
    if ($ok -and "$result" -match 'sim=([0-9a-f]+)') { $simSeen += $Matches[1] }
    if ($ok -and "$result" -match 'farben=(\S+)') { $colorsSeen += $Matches[1] }
    if ($ok -and "$result" -match 'musik=(\S+)') { $musicSeen += [pscustomobject]@{ Name = $run.Name; Samples = @($Matches[1] -split ';') } }
    if (-not $ok) { $failed++ }
    Write-Output ("[{0}] {1} ({2})" -f $(if ($ok) { 'OK    ' } else { 'FEHLER' }), $run.Name, $run.Args)
    foreach ($line in $lines | Where-Object { $_ -notmatch '(NETTEST|LOBBYTEST|APKTEST)-ERGEBNIS' -and $_ -match 'APK: |Ablehnung mit|neuere Version|ältere Version|Dateidienst|Hole Version|Gefunden:|Auch |Suchanfrage von|angenommen|abgelehnt|Abgelehnt|Senden an .* fehlgeschlagen|Ziele:|Ping |Start Runde|Alle haben geladen|In der Lobby|ZEICHENSTART|LINIEN DA|RENNEN ANGELEGT|SCHNAPPSCHUSS|Alle Menschen fertig|HÄNGER|weg \(' } | Select-Object -First 20) {
        Write-Output ("         " + ($line -replace '^\S+ \S+ \[\+\s*[\d.]+\] ', ''))
    }
    Write-Output ("         " + ("$result" -replace '^.*(NETTEST|LOBBYTEST|APKTEST)-ERGEBNIS: ', ''))
    foreach ($line in ($lines + $errors) | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR:' } | Select-Object -First 5) { Write-Output ("         ! " + $line) }
    Remove-Item -LiteralPath $run.Out, ($run.Out + '.err') -ErrorAction SilentlyContinue
}
Write-Output ''
if ($Lobby) {
    # M4: Alle, die mitgezeichnet haben, müssen dieselben Linien haben (Prüfsumme über alle verteilten Linien).
    $digests = @($digestSeen | Sort-Object -Unique)
    if ($digestSeen.Count -ne ($Clients + 1) -or $digests.Count -ne 1) { $failed++; Write-Output ("FEHLER: Prüfsummen der Linien: {0} gemeldet, {1} verschieden ({2})" -f $digestSeen.Count, $digests.Count, ($digests -join ', ')) }
    else { Write-Output ("Linien bei allen {0} Geräten gleich (Prüfsumme {1})." -f $digestSeen.Count, $digests[0]) }
    # M5: Wertung und Simulation bei allen gleich (der Host hat zusätzlich ohne Netz nachgerechnet: nachgerechnet=ja).
    $rows = @($rowsSeen | Sort-Object -Unique)
    $sims = @($simSeen | Sort-Object -Unique)
    if ($rowsSeen.Count -ne ($Clients + 1) -or $rows.Count -ne 1 -or $simSeen.Count -ne ($Clients + 1) -or $sims.Count -ne 1) {
        $failed++; Write-Output ("FEHLER: Wertung {0}× gemeldet ({1} verschieden), Simulation {2}× ({3} verschieden)" -f $rowsSeen.Count, $rows.Count, $simSeen.Count, $sims.Count)
    } else { Write-Output ("Wertung bei allen {0} Geräten gleich ({1}), Simulation {2}." -f $rowsSeen.Count, $rows[0], $sims[0]) }
    # Autowahl: Jedes Gerät zeigt dieselben Spielerfarben (Spieler-ID:Farbe), jede Farbe nur einmal (prüft lobby_cli.gd selbst).
    $colorSets = @($colorsSeen | Sort-Object -Unique)
    if ($colorsSeen.Count -ne ($Clients + 1) -or $colorSets.Count -ne 1) { $failed++; Write-Output ("FEHLER: Spielerfarben {0}× gemeldet, {1} verschieden ({2})" -f $colorsSeen.Count, $colorSets.Count, ($colorSets -join ' | ')) }
    else { Write-Output ("Spielerfarben bei allen {0} Geräten gleich ({1})." -f $colorsSeen.Count, $colorSets[0]) }
    # Musik: Alle spielen dasselbe Stück an derselben Stelle (Stelle 0 auf der Host-Uhr, höchstens 150 ms Abstand zum Host), 2 s nach dem
    # Start und nach der Wertung (gemeinsames Stück der Wertung, auch beim Mitspieler, der beim Laden 6 s hing).
    $hostMusic = @($musicSeen | Where-Object { $_.Name -eq 'Host' }) | Select-Object -First 1
    $musicBad = @()
    if ($musicSeen.Count -ne ($Clients + 1) -or -not $hostMusic) { $musicBad += ("{0}× gemeldet" -f $musicSeen.Count) }
    else {
        foreach ($m in $musicSeen) {
            for ($k = 0; $k -lt 2; $k++) {
                $want = "$($hostMusic.Samples[$k])" -split '@'
                $got = "$($m.Samples[$k])" -split '@'
                if ($got.Count -ne 2 -or $want.Count -ne 2 -or $got[0] -ne $want[0] -or [math]::Abs([long]$got[1] - [long]$want[1]) -gt 150) {
                    $musicBad += ("{0} Messpunkt {1}: {2} statt {3}" -f $m.Name, ($k + 1), $m.Samples[$k], $hostMusic.Samples[$k])
                }
            }
        }
    }
    if ($musicBad.Count -gt 0) { $failed++; Write-Output ("FEHLER: Musik nicht gleich: {0}" -f ($musicBad -join '; ')) }
    else {
        $spread = 0
        foreach ($m in $musicSeen) { for ($k = 0; $k -lt 2; $k++) { $spread = [math]::Max($spread, [math]::Abs([long]("$($m.Samples[$k])" -split '@')[1] - [long]("$($hostMusic.Samples[$k])" -split '@')[1])) } }
        Write-Output ("Musik bei allen {0} Geräten gleich: {1}, größter Abstand der Stelle {2} ms." -f $musicSeen.Count, ($hostMusic.Samples -join ' / '), $spread)
    }
}
# -Apk: Testdateien (Quellen und empfangene Kopien, gut 100 MB) wieder entfernen.
if ($Apk) { Remove-Item -LiteralPath (Join-Path $env:APPDATA 'Godot\app_userdata\Draw2Race\apktest') -Recurse -Force -ErrorAction SilentlyContinue }
if ($failed -gt 0) { Write-Output ("{0} von {1} Läufen fehlgeschlagen." -f $failed, $runs.Count); exit 1 }
if ($Lobby -or $Apk) { Write-Output ("Alle {0} Läufe OK." -f $runs.Count); exit 0 }
Write-Output ("Alle {0} Läufe OK. Protokolle: {1}" -f $runs.Count, (Join-Path $env:APPDATA 'Godot\app_userdata\Draw2Race\netztest_*.log'))
exit 0
