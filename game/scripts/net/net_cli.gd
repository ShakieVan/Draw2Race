extends SceneTree

# Automatik-Modus des Netztests für PC-Läufe ohne Spielablauf (tools/net_test.ps1 startet Host und Mitspieler als eigene Prozesse):
#   Godot --headless --path game --script res://scripts/net/net_cli.gd -- --nettest=host --nettest-expect=3
#   Godot --headless --path game --script res://scripts/net/net_cli.gd -- --nettest=join            (Host suchen, dann beitreten)
#   Godot --headless --path game --script res://scripts/net/net_cli.gd -- --nettest=join:127.0.0.1
# Optionen siehe scripts/net/net_test_screen.gd. Ergebniszeile „NETTEST-ERGEBNIS: …“, Exitcode 0 = OK.

const Screen := preload("res://scripts/net/net_test_screen.gd")

func _initialize() -> void:
	var options := Screen.cli_options()
	if options.is_empty():
		print("NETTEST-ERGEBNIS: FEHLER kein --nettest=host|join[:adresse]|search angegeben (Argumente nach --)")
		quit(2)
		return
	Screen.open(root, options)
