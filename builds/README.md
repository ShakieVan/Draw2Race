# Builds

Fertige Builds werden nicht im Repository abgelegt, sondern als Download unter **Releases** veröffentlicht (`Draw2Race-<Version>.apk`; der Updater erwartet diesen Namen).

`tools/build.ps1 -Target All` erzeugt lokal:

- `Draw2Race.apk` und eine Kopie `Draw2Race-<Version>.apk`: Android (ARM64/x86_64), signiert mit dem projekteigenen Debug-Schlüssel – Updates lassen sich ohne Deinstallation und ohne Verlust des Spielstands einspielen.
- `Draw2Race.exe`: Windows, direkt startbar.

Beim Weitergeben die Godot- und Outfit-Lizenzdateien beilegen (`game/assets/`). Die APK enthält sie als Ressourcen.

Jeder Build legt eine weitere versionierte APK (rund 300 MB) ab. Ältere Versionen können weg, sobald sie veröffentlicht sind; zuletzt wurde am 20.11.2026 aufgeräumt.
