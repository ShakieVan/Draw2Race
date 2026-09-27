@echo off
cd /d "%~dp0"
if exist "builds\Draw2Race.exe" (
    start "" "builds\Draw2Race.exe"
) else (
    start "" ".tools\Godot_v4.6.1-stable_win64.exe" --path "game"
)
