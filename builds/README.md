# Builds

Fertige Builds werden nicht im Repository abgelegt, sondern als Download unter **Releases** veröffentlicht (`Draw2Race.apk`).

`tools/build.ps1 -Target All` erzeugt lokal:

- `Draw2Race.apk`: Android (ARM64/x86_64), signiert mit dem projekteigenen Debug-Schlüssel – Updates lassen sich ohne Deinstallation und ohne Verlust des Spielstands einspielen.
- `Draw2Race.exe`: Windows, direkt startbar.

Beim Weitergeben die Godot- und Outfit-Lizenzdateien beilegen (`game/assets/`). Die APK enthält sie als Ressourcen.
