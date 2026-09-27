# Erzeugt die Spektrogramme und Messwerte der Tonanalyse in docs/reference/.
# Benötigt ffmpeg im Suchpfad. Aufruf vom Projektverzeichnis: powershell -File tools/analyze_audio.ps1
$ErrorActionPreference = 'Stop'
$video = 'Videos/DrawRace 2 - iPhone - NZ - HD Gameplay Trailer.mp4'
$out = 'docs/reference'

function Spec($name, $start, $duration, $size, $fscale, $fmin, $fmax) {
    $filter = "showspectrumpic=s=${size}:legend=1:fscale=${fscale}:scale=log:color=viridis:start=${fmin}:stop=${fmax}"
    ffmpeg -hide_banner -loglevel error -y -ss $start -t $duration -i $video -vn -ac 1 -ar 22050 -lavfi $filter "$out/audio_spec_$name.png"
}

ffmpeg -hide_banner -loglevel error -y -i $video -vn -ac 1 -ar 22050 -lavfi 'showspectrumpic=s=1800x500:legend=1:fscale=log:scale=log:color=viridis' "$out/audio_spec_gesamt.png"
Spec 'menu'        15    18  '1400x500' 'log' 40  11000
Spec 'start'       84.5  4.5 '1400x400' 'log' 100 11000
Spec 'startsignal' 85.9  2.4 '1200x600' 'lin' 700 2200
Spec 'motor'       87    14  '1400x600' 'lin' 40  900
Spec 'ergebnis'    113   20  '1400x500' 'log' 40  11000
Spec 'turbo'       325   24  '1400x500' 'log' 40  11000
Spec 'schnee'      772   20  '1400x500' 'log' 40  11000

# Stille (Szenenwechsel), Gesamtlautheit und Stereobreite (Seitensignal) ausgeben.
# ffmpeg schreibt Messwerte auf stderr; Windows PowerShell 5.1 würde das bei 'Stop' als Fehler werten.
$ErrorActionPreference = 'Continue'
ffmpeg -hide_banner -nostats -i $video -vn -af 'silencedetect=n=-45dB:d=0.7' -f null - 2>&1 | Select-String 'silence_'
ffmpeg -hide_banner -nostats -i $video -vn -af ebur128 -f null - 2>&1 | Select-Object -Last 12
ffmpeg -hide_banner -nostats -ss 325 -t 24 -i $video -af 'pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0-0.5*c1,astats=measure_overall=none:measure_perchannel=RMS_level' -f null - 2>&1 | Select-String 'Channel|RMS level'
