$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolDir = Join-Path $projectRoot '.tools'
$version = '4.6.1'
$base = "https://github.com/godotengine/godot-builds/releases/download/$version-stable"
New-Item -ItemType Directory -Force $toolDir | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $toolDir "Godot_v$version-stable_win64_console.exe"))) {
    $archive = Join-Path $toolDir 'godot.zip'
    Invoke-WebRequest "$base/Godot_v$version-stable_win64.exe.zip" -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $toolDir -Force
}
$templateDir = Join-Path $env:APPDATA "Godot/export_templates/$version.stable"
if (-not (Test-Path -LiteralPath (Join-Path $templateDir 'android_debug.apk'))) {
    $archive = Join-Path $toolDir 'templates.zip'
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-WebRequest "$base/Godot_v$version-stable_export_templates.tpz" -OutFile $archive
    }
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $toolDir 'export') -Force
    New-Item -ItemType Directory -Force $templateDir | Out-Null
    foreach ($file in @('android_debug.apk','android_release.apk','windows_release_x86_64.exe','windows_release_x86_64_console.exe','windows_debug_x86_64.exe','windows_debug_x86_64_console.exe')) {
        Copy-Item -LiteralPath (Join-Path $toolDir "export/templates/$file") -Destination $templateDir
    }
}
Write-Output 'Godot ist bereit. Android benötigt JDK 17 und ein Android SDK; Pfade bei Bedarf in den Godot-Editor-Einstellungen setzen.'
